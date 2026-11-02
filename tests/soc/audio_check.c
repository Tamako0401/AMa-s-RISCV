/* audio_check: 声音外设 (0x4000_8000) 挂在总线上、I2S 三根线经 GPIO 矩阵出得了引脚。
 * 频率、音量、I2S 时序的逐位核对在 tests/audio/audio_tb.sv; 这里只查接线:
 *   1. 寄存器读写得对 (DUTY 复位 128, FREQ 读回), 没打开时 SAMPLES 不动;
 *   2. 打开后 SAMPLES 在走, MIX 是 ±VOL×32;
 *   3. BCLK / LRCK / DOUT 接到 J8_4 / J8_5 / J8_6 (soc_tb +loopback 把输出电平送回输入), 读 IN 看得到它们在变。
 * 通过: main 返回 1。失败返回 0x20 + 第几步。 */
#include <stdint.h>

#include "audio.h"
#include "bsp.h"
#include "io.h"

int main(void)
{
    if (AUDIO->CH[0].DUTY != 128 || AUDIO->SAMPLES != 0 || AUDIO->CTRL != 0)
        return 0x21;
    audio_tone(AUDIO_SQUARE0, AUDIO_HZ(1000), 100, AUDIO_DUTY(50));
    if (AUDIO->CH[0].FREQ != 1365 || AUDIO->CH[0].VOL != 100)
        return 0x21;

    io_connect_out(PIN_J8_4, SIG_I2S_BCLK);
    io_connect_out(PIN_J8_5, SIG_I2S_LRCK);
    io_connect_out(PIN_J8_6, SIG_I2S_DOUT);
    audio_enable(1);
    uint32_t seen1 = 0, seen0 = 0, lr = 0;
    for (uint32_t n = 0; n < 20000 && AUDIO->SAMPLES < 8; n++) {
        uint32_t in = IO_MATRIX->IN[0];
        seen1 |= in;
        seen0 |= ~in;
        lr |= 1u << (in >> PIN_J8_5 & 1);
    }
    uint32_t samples = AUDIO->SAMPLES;
    if (samples < 8)
        return 0x22;
    int32_t mix = (int32_t)AUDIO->MIX;
    if (mix != 3200 && mix != -3200)
        return 0x22;
    uint32_t pins = 1u << PIN_J8_4 | 1u << PIN_J8_6;
    if ((seen1 & pins) != pins || (seen0 & pins) != pins || lr != 3)
        return 0x23;
    return 1;
}
