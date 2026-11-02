#include "audio_sdl.h"
#include "sound.h"
#include <SDL.h>
#include <string.h>

static SDL_AudioDeviceID device;
static struct {
    uint32_t ctrl, samples;
    uint16_t freq[4], phase[4], len[4], lfsr, under;
    uint8_t vol[4], duty[4], pcm_ctrl, pcm_vol, wait;
    int8_t fifo[2048], held;
    unsigned head, level;
    int16_t mix;
} a;
static void lock(void)
{
    if (device)
        SDL_LockAudioDevice(device);
}
static void unlock(void)
{
    if (device)
        SDL_UnlockAudioDevice(device);
}
void audio_sdl_reset(void)
{
    lock();
    memset(&a, 0, sizeof a);
    a.lfsr = 1;
    a.pcm_ctrl = 3 << 4;
    for (int ch = 0; ch < 4; ch++)
        a.duty[ch] = 128;
    unlock();
}
static void write_reg(uint32_t r, uint32_t v)
{
    if (r == 0)
        a.ctrl = v & 3;
    else if (r >= 0x10 && r < 0x50 && !(r & 3)) {
        unsigned ch = (r - 0x10) >> 4;
        switch (r & 15) {
        case 0:
            a.freq[ch] = v;
            break;
        case 4:
            a.vol[ch] = v;
            break;
        case 8:
            a.duty[ch] = v;
            break;
        case 12:
            a.len[ch] = v;
            break;
        }
    } else if (r == 0x50) {
        a.pcm_ctrl = v & 0xf1;
        if (!(v & 1)) {
            a.head = a.level = a.wait = 0;
            a.held = 0;
        }
    } else if (r == 0x54 && (a.pcm_ctrl & 1) && a.level <= 2044) {
        for (int i = 0; i < 4; i++) {
            a.fifo[(a.head + a.level++) & 2047] = (int8_t)(v >> (8 * i));
        }
    } else if (r == 0x5c)
        a.pcm_vol = v;
}
static uint32_t read_reg(uint32_t r)
{
    if (r == 0)
        return a.ctrl;
    if (r == 4)
        return a.samples;
    if (r == 8)
        return (uint32_t)(int32_t)a.mix;
    if (r == 0x50)
        return a.pcm_ctrl;
    if (r == 0x58)
        return a.level | ((uint32_t)a.under << 16);
    if (r == 0x5c)
        return a.pcm_vol;
    if (r >= 0x10 && r < 0x50 && !(r & 3)) {
        unsigned ch = (r - 0x10) >> 4;
        switch (r & 15) {
        case 0:
            return a.freq[ch];
        case 4:
            return a.vol[ch];
        case 8:
            return a.duty[ch];
        case 12:
            return a.len[ch];
        }
    }
    return 0;
}
void audio_reg_write(uint32_t r, uint32_t v)
{
    lock();
    write_reg(r, v);
    unlock();
}
uint32_t audio_reg_read(uint32_t r)
{
    lock();
    uint32_t v = read_reg(r);
    unlock();
    return v;
}
/* 一个 frame_tick: 先更新, 再混音; 输出上一帧的 mix, 与 RTL 的 I2S 装载顺序一致。
 * EXACT 仅影响物理时钟, 这里按约定固定每秒 48000 个样本。 */
static int16_t sample(void)
{
    if (!(a.ctrl & 1))
        return 0;
    int16_t out = a.mix;
    int sum = 0;
    for (int ch = 0; ch < 4; ch++) {
        unsigned phase = a.phase[ch] + a.freq[ch];
        a.phase[ch] = phase;
        if (ch == 3 && phase > 65535) {
            unsigned tap = a.duty[3] & 1 ? 6 : 1;
            unsigned fb = (a.lfsr ^ (a.lfsr >> tap)) & 1;
            a.lfsr = (a.lfsr >> 1) | (fb << 14);
        }
        if (a.len[ch] && !--a.len[ch])
            a.vol[ch] = 0;
        int high = ch == 3 ? a.lfsr & 1 : (a.phase[ch] >> 8) < a.duty[ch];
        if (a.freq[ch])
            sum += (high ? 1 : -1) * a.vol[ch] * 32;
    }
    if (a.pcm_ctrl & 1) {
        if (!a.wait) {
            unsigned div = a.pcm_ctrl >> 4;
            a.wait = (div ? div : 1) - 1;
            a.held = 0;
            if (a.level) {
                a.held = a.fifo[a.head];
                a.head = (a.head + 1) & 2047;
                a.level--;
            } else if (a.under != 65535)
                a.under++;
        } else
            a.wait--;
        sum += a.held * a.pcm_vol;
    }
    a.mix = sum > 32767 ? 32767 : sum < -32768 ? -32768 : sum;
    a.samples++;
    return out;
}
void audio_sdl_render(int16_t *out, int n)
{
    lock();
    for (int i = 0; i < n; i++)
        out[i] = sample();
    unlock();
}
static void callback(void *ctx, Uint8 *stream, int bytes)
{
    (void)ctx;
    int16_t *out = (int16_t *)stream;
    for (int i = 0; i < bytes / 2; i++)
        out[i] = sample();
}
int audio_sdl_init(int mute)
{
    audio_sdl_reset();
    audio_enable(1);
    if (mute || SDL_InitSubSystem(SDL_INIT_AUDIO))
        return 0;
    SDL_AudioSpec want = {0};
    want.freq = 48000;
    want.format = AUDIO_S16SYS;
    want.channels = 1;
    want.samples = 512;
    want.callback = callback;
    device = SDL_OpenAudioDevice(NULL, 0, &want, NULL, 0);
    if (device)
        SDL_PauseAudioDevice(device, 0);
    return device != 0;
}
void audio_sdl_close(void)
{
    if (device)
        SDL_CloseAudioDevice(device);
    device = 0;
}
void audio_enable(int on)
{
    audio_reg_write(0, on ? 1 : 0);
}
void audio_tone(uint32_t ch, uint32_t f, uint32_t v, uint32_t d)
{
    if (ch > 3)
        return;
    lock();
    unsigned r = 0x10 + ch * 16;
    write_reg(r + 12, 0);
    write_reg(r, f);
    write_reg(r + 8, d);
    write_reg(r + 4, v);
    unlock();
}
void audio_beep(uint32_t ch, uint32_t f, uint32_t v, uint32_t len)
{
    if (ch > 3)
        return;
    lock();
    unsigned r = 0x10 + ch * 16;
    write_reg(r, f);
    write_reg(r + 12, len);
    write_reg(r + 4, v);
    unlock();
}
void audio_noise(uint32_t f, uint32_t v, int short_mode, uint32_t len)
{
    lock();
    write_reg(0x40, f);
    write_reg(0x48, short_mode != 0);
    write_reg(0x4c, len);
    write_reg(0x44, v);
    unlock();
}
void audio_volume(uint32_t ch, uint32_t v)
{
    if (ch < 4)
        audio_reg_write(0x14 + ch * 16, v);
}
void audio_off(uint32_t ch)
{
    audio_volume(ch, 0);
}
int audio_busy(uint32_t ch)
{
    return ch < 4 && audio_reg_read(0x14 + ch * 16) != 0;
}
void audio_pcm_enable(int en, int div)
{
    audio_reg_write(0x50, (en ? 1 : 0) | ((div & 15) << 4));
}
int audio_pcm_space(void)
{
    return 2048 - (audio_reg_read(0x58) & 65535);
}
int audio_pcm_write(const int8_t *s, int n)
{
    lock();
    int count = 0;
    while (s && count + 4 <= n && a.level <= 2044 && (a.pcm_ctrl & 1)) {
        uint32_t v = 0;
        for (int i = 0; i < 4; i++)
            v |= (uint32_t)(uint8_t)s[count + i] << (8 * i);
        write_reg(0x54, v);
        count += 4;
    }
    unlock();
    return count;
}
void audio_pcm_volume(uint32_t v)
{
    audio_reg_write(0x5c, v);
}
void sound_hw_tone(unsigned ch, unsigned f, unsigned v, unsigned duty)
{
    audio_tone(ch, f, v, duty);
}
void sound_hw_noise(unsigned f, unsigned v, unsigned short_mode)
{
    audio_noise(f, v, short_mode, 0);
}
void sound_hw_off(unsigned ch)
{
    audio_off(ch);
}
