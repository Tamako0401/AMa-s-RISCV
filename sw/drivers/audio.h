/* 声音外设驱动: 3 个方波声道 + 1 个噪声声道, 寄存器见 amarisc.h, 说明见 docs/audio.md。
 * 只管寄存器; I2S 三根线接到哪个功放由 bsp/board_audio.h 决定 (board_audio_init)。
 * 全是 inline: 频率、时长是常量时编译期换算好 (rv32i 没有乘除法指令)。 */
#ifndef AUDIO_DRV_H
#define AUDIO_DRV_H

#include "amarisc.h"

#define AUDIO_RATE 48000 /* 采样率 (CTRL.EXACT 时是 48828) */
#define AUDIO_SQUARE0 0
#define AUDIO_SQUARE1 1
#define AUDIO_SQUARE2 2
#define AUDIO_NOISE 3
#define AUDIO_VOL_MAX 255 /* 四个声道都开满也不会溢出 */

/* 频率 (Hz) 换成 FREQ 寄存器的值, 分辨率约 0.73 Hz, 最高 24 kHz。噪声声道: LFSR 每秒走 hz 步 */
#define AUDIO_HZ(hz) ((uint32_t)(((uint32_t)(hz) * 65536UL + AUDIO_RATE / 2) / AUDIO_RATE))
/* 毫秒换成 LEN 的值 (采样数), 最长 1365 ms */
#define AUDIO_MS(ms) ((uint32_t)(ms) * (AUDIO_RATE / 1000))
/* 占空比 (百分比) 换成 DUTY 的值 */
#define AUDIO_DUTY(percent) ((uint32_t)(percent) * 256 / 100)

static inline void audio_enable(int on)
{
    AUDIO->CTRL = on ? AUDIO_CTRL_EN : 0;
}

/* 方波一直响: freq = AUDIO_HZ(...), vol 0~255, duty = AUDIO_DUTY(...) (50% 最响, 12.5% 尖) */
static inline void audio_tone(uint32_t ch, uint32_t freq, uint32_t vol, uint32_t duty)
{
    AUDIO->CH[ch].LEN = 0;
    AUDIO->CH[ch].FREQ = freq;
    AUDIO->CH[ch].DUTY = duty;
    AUDIO->CH[ch].VOL = vol;
}

/* 响一段就自己停: len = AUDIO_MS(...)。不用等它, 主循环照常跑 */
static inline void audio_beep(uint32_t ch, uint32_t freq, uint32_t vol, uint32_t len)
{
    AUDIO->CH[ch].FREQ = freq;
    AUDIO->CH[ch].LEN = len;
    AUDIO->CH[ch].VOL = vol;
}

/* 噪声: rate = AUDIO_HZ(LFSR 每秒走几步, 越大越 "嘶"), short_mode 1 = 93 步一轮 (有音高的金属声) */
static inline void audio_noise(uint32_t rate, uint32_t vol, int short_mode, uint32_t len)
{
    AUDIO->CH[AUDIO_NOISE].FREQ = rate;
    AUDIO->CH[AUDIO_NOISE].DUTY = short_mode ? AUDIO_DUTY_SHORT : 0;
    AUDIO->CH[AUDIO_NOISE].LEN = len;
    AUDIO->CH[AUDIO_NOISE].VOL = vol;
}

/* 改音量 (做渐弱、包络: 每帧调一次) */
static inline void audio_volume(uint32_t ch, uint32_t vol)
{
    AUDIO->CH[ch].VOL = vol;
}

static inline void audio_off(uint32_t ch)
{
    AUDIO->CH[ch].VOL = 0;
}

/* 这个声道还在响吗 (audio_beep 放完了 VOL 会变 0) */
static inline int audio_busy(uint32_t ch)
{
    return AUDIO->CH[ch].VOL != 0;
}

/* PCM 共同约定的最小软件实现。硬件来自任务 A; 合并时保留一份同名接口。 */
#define AUDIO_PCM_REG(off) (*(volatile uint32_t *)(AUDIO_BASE + (off)))
static inline void audio_pcm_enable(int en, int div)
{
    AUDIO_PCM_REG(0x50) = (en ? 1u : 0u) | ((uint32_t)(div & 15) << 4);
}
static inline int audio_pcm_space(void)
{
    uint32_t level = AUDIO_PCM_REG(0x58) & 65535;
    return level < 2048 ? (int)(2048 - level) : 0;
}
static inline int audio_pcm_write(const int8_t *s, int n)
{
    int space = audio_pcm_space();
    if (n > space)
        n = space;
    n &= ~3;
    for (int i = 0; i < n; i += 4)
        AUDIO_PCM_REG(0x54) = (uint8_t)s[i] | (uint32_t)(uint8_t)s[i + 1] << 8 | (uint32_t)(uint8_t)s[i + 2] << 16 |
                              (uint32_t)(uint8_t)s[i + 3] << 24;
    return n;
}
static inline void audio_pcm_volume(uint32_t v)
{
    AUDIO_PCM_REG(0x5c) = v & 255;
}

#endif
