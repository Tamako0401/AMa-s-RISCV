/* game/board 输入部分的主机测试。
 *   link.c: 打的字和帧混在一起能拆开, 坏帧丢掉, 断了能在下一个 0xFF 重新对上;
 *   pad.c: 两个口 (控制台串口、第二个串口) 来的字和 'P' 帧一样处理, 各口解析器互不干扰, 按键合起来, 断了会松开。 */
#include <stdio.h>
#include <string.h>
#include "link.c"
#define PAD_NO_UART /* 只编 pad_begin / pad_byte / pad_end, 不读串口 */
#include "pad.c"

static int failures;

static void check(int passed, const char *name)
{
    printf("%s: %s\n", passed ? "PASS" : "FAIL", name);
    if (!passed)
        failures++;
}

/* 喂一串字节: 打的字依次存进 text, 收齐的帧存进 frames, 返回帧数 */
static int feed(link_t *link, const uint8_t *in, int n, char *text, link_frame_t *frames)
{
    int count = 0, t = 0;
    for (int i = 0; i < n; i++) {
        int got = link_byte(link, in[i]);
        if (got == LINK_TEXT)
            text[t++] = (char)in[i];
        else if (got == LINK_FRAME)
            frames[count++] = link->frame;
    }
    text[t] = 0;
    return count;
}

/* 拼一个 'P' 帧 (keys, btn, x, y), 返回字节数 */
static int pad_frame(uint8_t *out, uint8_t keys, uint8_t btn, uint32_t x, uint32_t y)
{
    uint8_t d[6] = {keys, btn, (uint8_t)(x >> 7), (uint8_t)(x & 127), (uint8_t)(y >> 7), (uint8_t)(y & 127)};
    uint32_t sum = 'P' + 6;
    out[0] = 0xFF;
    out[1] = 'P';
    out[2] = 6;
    for (int i = 0; i < 6; i++) {
        out[3 + i] = d[i];
        sum += d[i];
    }
    out[9] = sum & 127;
    return 10;
}

/* 一帧: 依次把 bytes[k] 喂给 port[k] (交错着来), 再结束这一帧 */
static void pad_step(pad_t *pad, const uint8_t *bytes, const uint8_t *ports, int n)
{
    pad_begin(pad);
    for (int i = 0; i < n; i++)
        pad_byte(pad, ports[i], bytes[i]);
    pad_end(pad);
}

/* 一帧, 所有字节都从 port 来 */
static void pad_feed(pad_t *pad, uint32_t port, const uint8_t *bytes, int n)
{
    uint8_t ports[64];
    memset(ports, (int)port, sizeof ports);
    pad_step(pad, bytes, ports, n);
}

static int other_frames;
static void on_frame(const link_frame_t *f, void *ctx)
{
    (void)ctx;
    if (f->type == 'Z')
        other_frames++;
}

static void pad_tests(void)
{
    uint8_t buf[64], ports[64];
    for (uint32_t port = 0; port < PAD_PORTS; port++) {
        pad_t pad = {0};
        /* 终端打的字: 两个口都认, 按住 PAD_HOLD 帧 */
        pad_feed(&pad, port, (const uint8_t *)"w", 1);
        int held = 1;
        for (int i = 1; i < PAD_HOLD; i++) {
            pad_feed(&pad, port, buf, 0);
            held &= (pad.held & PAD_UP) != 0;
        }
        pad_feed(&pad, port, buf, 0);
        check(held && pad.held == 0, port ? "第二个口: 打的字按住 PAD_HOLD 帧" : "控制台口: 打的字按住 PAD_HOLD 帧");
        /* 方向键 ESC [ A 和单按 Esc */
        pad_feed(&pad, port, (const uint8_t *)"\x1b[A", 3);
        check(pad.held == PAD_UP, "ESC [ A 是上");
        pad_feed(&pad, port, (const uint8_t *)"\x1b", 1);
        pad_feed(&pad, port, buf, 0);
        check(pad.pressed & PAD_MENU, "单按 Esc 是 MENU");
        /* 'P' 帧: A + 鼠标左键, 鼠标在窗口里 */
        pad = (pad_t){0};
        int n = pad_frame(buf, PAD_A, 0x0C, 639, 360);
        pad_feed(&pad, port, buf, n);
        check(pad.held == (PAD_A | PAD_CLICK) && (pad.pressed & PAD_A) && pad.mouse && pad.mx == 639 && pad.my == 360,
              port ? "第二个口的 'P' 帧" : "控制台口的 'P' 帧");
    }

    /* 两个口交错着来字节, 各自的解析器不乱; 两个口的按键合起来 */
    pad_t pad = {0};
    int n0 = pad_frame(buf, PAD_LEFT, 0, 0, 0);
    int n1 = pad_frame(buf + 32, PAD_A, 0, 0, 0);
    uint8_t mixed[64];
    int n = 0;
    for (int i = 0; i < n0 || i < n1; i++) {
        if (i < n0) {
            mixed[n] = buf[i];
            ports[n++] = 0;
        }
        if (i < n1) {
            mixed[n] = buf[32 + i];
            ports[n++] = 1;
        }
    }
    pad_step(&pad, mixed, ports, n);
    check(pad.held == (PAD_LEFT | PAD_A), "两个口交错的帧都收到, 按键合起来");
    /* 一个口松开不影响另一个口 */
    n = pad_frame(buf, 0, 0, 0, 0);
    pad_feed(&pad, 0, buf, n);
    check(pad.held == PAD_A, "控制台口松开, 第二个口的 A 还按着");

    /* 第二个口不再发 'P' 帧: PAD_STALE 帧后松开; 控制台口一直在发的照常 */
    int still = 1;
    for (int i = 2; i < PAD_STALE; i++) { /* 发 A 的那帧算 0, 松开 0 号口那帧算 1 */
        n = pad_frame(buf, PAD_B, 0, 0, 0);
        pad_feed(&pad, 0, buf, n);
        still &= pad.held == (PAD_A | PAD_B);
    }
    n = pad_frame(buf, PAD_B, 0, 0, 0);
    pad_feed(&pad, 0, buf, n);
    check(still && pad.held == PAD_B, "断了的口 PAD_STALE 帧后松开");

    /* 鼠标: 在窗口里的口优先 */
    pad = (pad_t){0};
    n0 = pad_frame(buf, 0, 0x04, 100, 50);
    pad_feed(&pad, 1, buf, n0);
    n0 = pad_frame(buf, 0, 0, 7, 7);
    pad_feed(&pad, 0, buf, n0);
    check(pad.mouse && pad.mx == 100 && pad.my == 50, "鼠标位置跟着鼠标在窗口里的口");

    /* 'P' 以外的帧从哪个口来都交给 on_frame */
    pad = (pad_t){.on_frame = on_frame};
    static const uint8_t z[] = {0xFF, 'Z', 0, 'Z' & 127};
    pad_feed(&pad, 0, z, sizeof z);
    pad_feed(&pad, 1, z, sizeof z);
    check(other_frames == 2, "别的帧两个口都交给 on_frame");

    /* 一个口里半帧, 另一个口打的字照常是字 */
    pad = (pad_t){0};
    n = pad_frame(buf, PAD_DOWN, 0, 0, 0);
    pad_feed(&pad, 0, buf, 5);
    pad_feed(&pad, 1, (const uint8_t *)"d", 1);
    check(pad.held == PAD_RIGHT, "一个口半帧时另一个口打字");
    pad_feed(&pad, 0, buf + 5, n - 5);
    check(pad.held == (PAD_RIGHT | PAD_DOWN), "半帧下一帧接着收齐");
}

int main(void)
{
    link_t link = {0};
    char text[64];
    link_frame_t frames[8];

    /* 'P' 帧, 数据 [0x11, 0x08, 4, 127, 2, 104] (x = 639, y = 360): 校验 = (0x50 + 6 + 数据之和) & 127 */
    static const uint8_t pad[] = {0xFF, 'P', 6, 0x11, 0x08,
                                  4,    127, 2, 104,  (0x50 + 6 + 0x11 + 0x08 + 4 + 127 + 2 + 104) & 127};
    uint8_t in[64];
    int n = 0;
    in[n++] = 'w';
    for (unsigned i = 0; i < sizeof pad; i++)
        in[n++] = pad[i];
    in[n++] = 'j';
    int got = feed(&link, in, n, text, frames);
    check(got == 1 && frames[0].type == 'P' && frames[0].len == 6, "一帧收齐");
    check(got == 1 && link_u14(frames[0].data + 2) == 639 && link_u14(frames[0].data + 4) == 360, "14 位数拼回");
    check(text[0] == 'w' && text[1] == 'j' && text[2] == 0, "帧前后打的字照样是字");

    uint8_t bad[sizeof pad];
    for (unsigned i = 0; i < sizeof pad; i++)
        bad[i] = pad[i];
    bad[sizeof pad - 1] ^= 1;
    check(feed(&link, bad, sizeof bad, text, frames) == 0, "校验不对丢掉");

    /* 半帧被新的 0xFF 打断, 后面的整帧照样收到 */
    n = 0;
    for (unsigned i = 0; i < 5; i++)
        in[n++] = pad[i];
    for (unsigned i = 0; i < sizeof pad; i++)
        in[n++] = pad[i];
    check(feed(&link, in, n, text, frames) == 1 && text[0] == 0, "半帧被下一个帧头打断");

    /* 帧里出现 0x80 以上的字节 (不是 0xFF): 整帧作废, 之后回到打字 */
    static const uint8_t broken[] = {0xFF, 'P', 6, 0x11, 0x90, 'q'};
    got = feed(&link, broken, sizeof broken, text, frames);
    check(got == 0 && text[0] == 'q' && text[1] == 0, "帧里有坏字节");

    static const uint8_t too_long[] = {0xFF, 'X', LINK_MAX + 1, 'a'};
    got = feed(&link, too_long, sizeof too_long, text, frames);
    check(got == 0 && text[0] == 'a', "长度超过 LINK_MAX 丢掉");

    static const uint8_t empty[] = {0xFF, 'Z', 0, ('Z' + 0) & 127};
    got = feed(&link, empty, sizeof empty, text, frames);
    check(got == 1 && frames[0].type == 'Z' && frames[0].len == 0, "没有数据的帧");

    check(feed(&link, (const uint8_t *)"\x80\xfe", 2, text, frames) == 0 && text[0] == 0, "帧外的高位字节不算字");

    pad_tests();

    printf("%d failure(s)\n", failures);
    return failures != 0;
}
