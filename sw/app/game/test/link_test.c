/* game/board/link.c 的主机测试: 打的字和帧混在一起能拆开, 坏帧丢掉, 断了能在下一个 0xFF 重新对上 */
#include <stdio.h>
#include "../../../../game/board/link.c"

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

    printf("%d failure(s)\n", failures);
    return failures != 0;
}
