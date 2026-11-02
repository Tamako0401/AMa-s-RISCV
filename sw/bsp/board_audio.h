/* 板上的功放: 声音外设 (drivers/audio.h) 的 I2S 三根线经 GPIO 矩阵接到哪, 换板或换脚只改这里。
 *   mes2l100hp: GameShield 上的 MAX98357A 模块 (J3), BCLK / LRCK / DIN 接 AMP_BCLK / AMP_LRCK / AMP_DIN;
 *               AMP_SD 当普通 GPIO 拉高 = 开机 (拉到 3.3 V 时只放左声道, 外设左右声道是同一个样本)。
 *   其他板没有功放: 只打开外设 (BCLK 不出引脚), 程序照常调 audio_* 不出声。
 * 只有头文件: 不用改 ama 的源文件列表. */
#ifndef BOARD_AUDIO_H
#define BOARD_AUDIO_H

#include "audio.h"
#include "bsp.h"
#include "io.h"

/* 打开声音外设和功放; 之后用 audio_tone / audio_beep 出声 */
static inline void board_audio_init(void)
{
    audio_enable(1);
#ifdef PIN_AMP_BCLK
    io_connect_out(PIN_AMP_BCLK, SIG_I2S_BCLK);
    io_connect_out(PIN_AMP_LRCK, SIG_I2S_LRCK);
    io_connect_out(PIN_AMP_DIN, SIG_I2S_DOUT);
    io_write(PIN_AMP_SD, 1); /* 先有时钟再开功放 */
    io_dir(PIN_AMP_SD, IO_OUTPUT);
#endif
}

/* 关功放 (SD 拉低 = 关断) 和外设 */
static inline void board_audio_off(void)
{
#ifdef PIN_AMP_SD
    io_write(PIN_AMP_SD, 0);
#endif
    audio_enable(0);
}

#endif
