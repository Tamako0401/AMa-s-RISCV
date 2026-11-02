/* 手算寄存器序列: 每次 render 先送上一帧 mix, 再执行相位/LEN/混音。 */
#include "audio_sdl.h"
#include <assert.h>
#include <stdio.h>

static int16_t out[256];
static void reset(void)
{
    audio_sdl_reset();
    audio_enable(1);
}
static void expect(const int16_t *want, int n)
{
    audio_sdl_render(out, n);
    for (int i = 0; i < n; i++) {
        if (out[i] != want[i])
            fprintf(stderr, "sample %d: %d != %d\n", i, out[i], want[i]);
        assert(out[i] == want[i]);
    }
}
static void square(void)
{
    reset();
    /* 相位 4000,8000,c000,0000; duty=128 => +,-,-,+, 幅度 2*32。 */
    audio_tone(0, 0x4000, 2, 128);
    const int16_t wave[] = {0, 64, -64, -64, 64};
    expect(wave, 5);
    assert(audio_reg_read(4) == 5);
    reset();
    audio_tone(0, 0x4000, 2, 64); /* 阈值相等归负 */
    const int16_t narrow[] = {0, -64, -64, -64, 64};
    expect(narrow, 5);
    reset();
    audio_tone(0, 0x4000, 2, 128);
    audio_beep(0, 0x4000, 2, 3);
    const int16_t len[] = {0, 64, -64, 0, 0};
    expect(len, 5);
    assert(!audio_busy(0) && audio_reg_read(0x1c) == 0);
    audio_enable(0);
    audio_sdl_render(out, 10);
    assert(audio_reg_read(4) == 5);
    for (int i = 0; i < 10; i++)
        assert(out[i] == 0);
    reset();
    audio_tone(0, 0, 255, 128);
    audio_sdl_render(out, 10);
    for (int i = 0; i < 10; i++)
        assert(out[i] == 0);
}
static void noise(void)
{
    /* 每两帧溢出一次。前 20 次溢出的 LFSR, 由移位与 XOR 手推。
     * 长: 4000 -> ... -> 0002 -> 4001; 短: 0040 -> 4020。 */
    static const uint16_t state[2][21] = {
        {1,    0x4000, 0x2000, 0x1000, 0x800,  0x400,  0x200,  0x100,  0x80,  0x40, 0x20,
         0x10, 8,      4,      2,      0x4001, 0x6000, 0x3000, 0x1800, 0xc00, 0x600},
        {1,      0x4000, 0x2000, 0x1000, 0x800, 0x400,  0x200,  0x100,  0x80,   0x40,  0x4020,
         0x2010, 0x1008, 0x804,  0x402,  0x201, 0x4100, 0x2080, 0x1040, 0x4820, 0x2410},
    };
    for (int mode = 0; mode < 2; mode++) {
        reset();
        audio_noise(0x8000, 1, mode, 0);
        audio_sdl_render(out, 42);
        assert(out[0] == 0);
        for (int i = 1; i < 42; i++)
            assert(out[i] == (state[mode][i / 2] & 1 ? 32 : -32));
    }
    reset();
    audio_noise(0x8000, 1, 1, 0);
    int16_t cycle[373];
    audio_sdl_render(cycle, 373);
    for (int i = 1; i <= 186; i++)
        assert(cycle[i] == cycle[i + 186]);
    reset();
    audio_noise(0x8000, 1, 0, 0);
    audio_sdl_render(cycle, 373);
    int differs = 0;
    for (int i = 1; i <= 186; i++)
        differs |= cycle[i] != cycle[i + 186];
    assert(differs);
}
static void pcm(void)
{
    reset();
    audio_pcm_enable(1, 3);
    audio_pcm_volume(2);
    /* 小端 1,-2,127,-128, 每个样本保留三帧; 空后归零, 每三帧欠载一次。 */
    audio_reg_write(0x54, 0x807ffe01u);
    const int16_t want[] = {0, 2, 2, 2, -4, -4, -4, 254, 254, 254, -256, -256, -256, 0, 0, 0, 0};
    expect(want, 17);
    assert(audio_reg_read(0x58) == 2u << 16);
    audio_pcm_enable(0, 3);
    assert(audio_pcm_space() == 2048);
    audio_pcm_enable(1, 0);
    int8_t samples[2052] = {0};
    samples[0] = 127;
    assert(audio_pcm_write(samples, 2052) == 2048);
    assert(audio_pcm_space() == 0);
    assert(audio_pcm_write(samples, 4) == 0);
    audio_reg_write(0x54, 0x01010101);
    assert(audio_pcm_space() == 0);
    audio_sdl_render(out, 1);
    assert(audio_pcm_space() == 1); /* DIV=0 等价 1 */
    assert(audio_pcm_write(samples, 4) == 0);
    audio_pcm_enable(0, 1);
    assert(audio_pcm_write(samples, 4) == 0);
    assert(audio_pcm_space() == 2048);
    audio_pcm_enable(1, 1);
    assert(audio_pcm_write(samples, 7) == 4);
    audio_pcm_enable(0, 1);
    audio_pcm_enable(1, 1);
    for (int i = 0; i < 66000; i++)
        audio_sdl_render(out, 1);
    assert(audio_reg_read(0x58) >> 16 == 65535);
}
static void fifo_wrap(void)
{
    reset();
    audio_pcm_enable(1, 1);
    audio_pcm_volume(1);
    int8_t first[2048], next[512];
    for (int i = 0; i < 2048; i++)
        first[i] = (int8_t)(i % 100);
    for (int i = 0; i < 512; i++)
        next[i] = -7;
    assert(audio_pcm_write(first, 2048) == 2048);
    audio_sdl_render(out, 256);
    audio_sdl_render(out, 256);
    assert(audio_pcm_write(next, 512) == 512);
    for (int i = 0; i < 2049; i++) {
        audio_sdl_render(out, 1);
        assert(out[0] == (i <= 1536 ? first[i + 511] : -7));
    }
    assert(audio_pcm_space() == 2048 && audio_reg_read(0x58) >> 16 == 1);
}
static void saturation(void)
{
    for (int neg = 0; neg < 2; neg++) {
        reset();
        for (int ch = 0; ch < 3; ch++)
            audio_tone(ch, 1, 255, neg ? 0 : 128);
        audio_noise(1, 255, 0, 0);
        if (neg)
            audio_off(3); /* 三路 -8160 */
        audio_pcm_enable(1, 1);
        audio_pcm_volume(255);
        audio_reg_write(0x54, neg ? 0x80808080u : 0x7f7f7f7fu);
        audio_sdl_render(out, 2);
        assert(out[0] == 0 && out[1] == (neg ? -32768 : 32767));
    }
}
int main(void)
{
    square();
    noise();
    pcm();
    saturation();
    fifo_wrap();
    puts("audio: 手算样本、长短 LFSR、LEN、PCM FIFO/DIV/欠载/饱和通过");
    return 0;
}
