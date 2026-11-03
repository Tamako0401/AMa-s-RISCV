/* pcm_test: 板上单独测 PCM 声道, 不用 SD 卡和游戏 (和 game 同一个位流)。
 * 内存里合成 16 kHz 8 位正弦, 按游戏的节奏喂: 每 1/60 秒补到 800 样本 (同 game/core/mix.c)。
 * 功放和 HDMI 同时出声; HDMI 画面是纯色底 (深蓝 = 发送芯片配好, 红 = 没应答或音频设置失败)。
 * 串口每秒一行: 这一秒出了几个采样 (应 48000, EXACT 时 48828)、FIFO 剩几个样本、欠载累计和这一秒新增。
 * 串口按键 (ama monitor):
 *   1  PCM 440 Hz 正弦 (开机默认)
 *   2  PCM 音阶 C5~C6, 每音 0.5 秒 (听音高准不准, 有没有抖)
 *   3  响度对比: PCM 440 Hz 正弦 / 方波 440 Hz (VOL 128, 游戏音效音量 12~160) 每秒交替
 *   4  断粮: 停喂 0.2 秒, 欠载应涨约 2400~2700 (3200 减去队列里的 800; 会听到一下断), 之后恢复
 *   5  满队列: 写到 2048, 查 LEVEL 不超过 2048、再写一字被丢; 之后自己放回 800
 *   0  静音 (继续喂 0, 欠载不该涨)
 *   e  切 EXACT (整数分频 BCLK, 没抖动, 音高高 1.7%), 显示器不出声时试它
 *   + / -  PCM 音量 ±16 (游戏用 96) */
#include "board_audio.h"
#include "board_hdmi.h"
#include "bsp.h"
#include "uart.h"

#define RATE 16000
#define TARGET 800 /* 同 MIX_TARGET */
#define FRAME (SYSCLK_HZ / 60)

static const int8_t quarter[65] = {0,   3,   6,   9,   12,  16,  19,  22,  25,  28,  31,  34,  37,  40,  43,  46,  49,
                                   51,  54,  57,  60,  63,  65,  68,  71,  73,  76,  78,  81,  83,  85,  88,  90,  92,
                                   94,  96,  98,  100, 102, 104, 106, 107, 109, 111, 112, 113, 115, 116, 117, 118, 120,
                                   121, 122, 122, 123, 124, 125, 125, 126, 126, 126, 127, 127, 127, 127};
/* C5 D5 E5 F5 G5 A5 B5 C6, 单位 0.01 Hz */
static const uint32_t scale[8] = {52325, 58733, 65926, 69846, 78399, 88000, 98777, 104650};

static int8_t sine(uint32_t phase)
{
    uint32_t i = phase >> 24; /* 0~255 一整圈 */
    int8_t v = quarter[i & 64 ? 64 - (i & 63) : i & 63];
    return i & 128 ? (int8_t)-v : v;
}

static uint32_t step_of(uint32_t centi_hz)
{
    return (uint32_t)(((uint64_t)centi_hz << 32) / (RATE * 100u));
}

static void put_num(uint32_t n)
{
    char buf[11];
    int i = 10;
    buf[i] = 0;
    do {
        buf[--i] = (char)('0' + n % 10);
        n /= 10;
    } while (n);
    uart_puts(CONSOLE_UART, buf + i);
}

static void say(const char *s)
{
    uart_puts(CONSOLE_UART, s);
}

static uint32_t underruns(void)
{
    return AUDIO->PCM_LEVEL >> 16;
}

static uint32_t level(void)
{
    return AUDIO->PCM_LEVEL & 0xffffu;
}

static void screen(uint16_t rgb565)
{
    volatile uint32_t *d = (volatile uint32_t *)0x30000000;
    for (uint32_t i = 0; i < 160 * 45; i++) /* 文字层: 上一个程序留下的字清掉 */
        d[0x20000 / 4 + i] = 0;
    d[0] = 1;      /* CTRL: 开显示, 不开小窗 */
    d[1] = rgb565; /* BACKDROP */
    d[2] = 0;      /* CLIP: 不画背景 */
    d[5] = 0;      /* FADE */
    d[6] = 0;      /* SPRITE_N */
    d[7] = 1;      /* COMMIT */
}

static uint32_t phase, step;
static int silent;

/* 补到 TARGET, 返回写了几个 */
static int feed(void)
{
    int need = (audio_pcm_space() - (2048 - TARGET)) & ~3;
    int done = 0;
    while (need > 0) {
        int8_t buf[64];
        int n = need > 64 ? 64 : need;
        for (int i = 0; i < n; i++) {
            buf[i] = silent ? 0 : sine(phase);
            phase += step;
        }
        audio_pcm_write(buf, n);
        need -= n;
        done += n;
    }
    return done;
}

static void full_test(void)
{
    int8_t buf[64];
    do
        for (int i = 0; i < 64; i++) {
            buf[i] = silent ? 0 : sine(phase);
            phase += step;
        }
    while (audio_pcm_write(buf, 64));
    uint32_t before = level();
    AUDIO->PCM_DATA = 0x01010101u; /* 不足四个空位: 整字丢 */
    uint32_t after = level();
    say("full: level ");
    put_num(before);
    say(" -> extra word -> ");
    put_num(after);
    say(before >= 2040 && before <= 2048 && after <= before ? "  ok\r\n" : "  BAD\r\n");
}

int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    int hdmi = board_hdmi_init();
    say(hdmi & 1 ? "pcm_test: HDMI TX no answer / audio setup failed\r\n" : "pcm_test: HDMI TX ok\r\n");
    screen(hdmi & 1 ? 0xF800 : 0x0010);

    /* 照 docs/audio.md: 总开关关着时开 PCM、预填, 再开总开关, 开头不欠载 */
    audio_enable(0);
    audio_pcm_enable(0, 3);
    audio_pcm_enable(1, 3);
    uint32_t vol = 96;
    audio_pcm_volume(vol);
    step = step_of(44000);
    feed();
    board_audio_init();
    uint32_t ctrl = AUDIO_CTRL_EN;
    say("keys: 1 sine  2 scale  3 PCM/square  4 starve  5 full  0 mute  e EXACT  +/- volume\r\n");

    char mode = '1';
    uint32_t frame = 0, starve = 0, next = bsp_cycles() + FRAME;
    uint32_t last_samples = AUDIO->SAMPLES, last_under = underruns(), min_level = 2048;
    for (;;) {
        char c;
        if (uart_getc(CONSOLE_UART, &c)) {
            if (c == '4') {
                starve = 12;
                say("starve 0.2 s\r\n");
            } else if (c == '5')
                full_test();
            else if (c >= '0' && c <= '3') {
                if (mode == '3')
                    audio_off(AUDIO_SQUARE0);
                mode = c;
                silent = c == '0';
                step = step_of(44000);
                frame = 0;
            } else if (c == 'e') {
                ctrl ^= AUDIO_CTRL_EXACT;
                AUDIO->CTRL = ctrl;
                say(ctrl & AUDIO_CTRL_EXACT ? "EXACT on (48828 Hz, no jitter)\r\n" : "EXACT off\r\n");
            } else if (c == '+' || c == '-') {
                vol = c == '+' ? (vol > 239 ? 255 : vol + 16) : (vol < 16 ? 0 : vol - 16);
                audio_pcm_volume(vol);
                say("PCM volume ");
                put_num(vol);
                say("\r\n");
            }
        }
        if ((int32_t)(bsp_cycles() - next) < 0)
            continue;
        next += FRAME;
        frame++;

        if (mode == '2')
            step = step_of(scale[frame / 30 % 8]);
        if (mode == '3') {
            int square = frame / 60 % 2;
            silent = square;
            if (square)
                audio_tone(AUDIO_SQUARE0, AUDIO_HZ(440), 128, AUDIO_DUTY(50));
            else
                audio_off(AUDIO_SQUARE0);
            if (frame % 60 == 0)
                say(square ? "  square VOL 128\r\n" : "  PCM sine\r\n");
        }
        uint32_t l = level();
        if (l < min_level)
            min_level = l;
        if (starve)
            starve--;
        else
            feed();

        if (frame % 60 == 0) {
            uint32_t samples = AUDIO->SAMPLES, under = underruns();
            say("rate ");
            put_num(samples - last_samples);
            say(" Hz, level min ");
            put_num(min_level);
            say(", underrun ");
            put_num(under);
            say(" (+");
            put_num(under - last_under);
            say(")\r\n");
            last_samples = samples;
            last_under = under;
            min_level = 2048;
        }
    }
}
