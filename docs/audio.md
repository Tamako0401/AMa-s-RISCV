# 声音

`rtl/perips/audio.v`, 映射到 `0x4000_8000`: 3 个方波声道 + 1 个噪声声道, 混成 16 位, 标准 I2S 输出。
像老游戏机的声音芯片: CPU 只写频率、音量, 波形由硬件每个采样算一次, 不用 CPU 喂样本, 不用块 RAM。

```
声道 0~2 (方波: FREQ / VOL / DUTY / LEN) ─┐
声道 3   (噪声: FREQ / VOL / 短周期 / LEN) ─┼─> 相加 (16 位) ─> I2S 移位 ─> BCLK / LRCK / DOUT ─> GPIO 矩阵 ─> 功放
                                           ┘   每个采样一次          48 kHz, 64 BCLK 一帧        信号 5 / 6 / 7
```

## I2S 输出

- 标准 I2S (Philips): LRCK 低 = 左声道, 左右各 32 位槽, 数据 MSB 先发, LRCK 变后晚一个 BCLK 才发最高位 (一位延迟)。
  BCLK 下降沿换数据, 接收方上升沿采。16 位样本高位对齐, 槽里其余 16 位补 0; 左右声道是同一个样本。
- 采样率 48 kHz, BCLK = 64 × 48 kHz = 3.072 MHz, 不出 MCLK。MAX98357A (I2S 版; B 版是左对齐, 不能用) 直接吃。
- BCLK 由 50 MHz 系统时钟相位累加得到 (每 3125 拍 384 个边沿): 平均频率精确, 每个边沿最多抖一个系统时钟 (20 ns),
  半周期是 8 或 9 拍。方法同 HDMI 音频 spike (`i2s_beep.v`)。
- CTRL.EXACT = 1: 改成系统时钟 16 分频 (BCLK 3.125 MHz, 采样率 48.828 kHz), 没有抖动, 音高都高 1.7%。
  给对 BCLK 抖动挑剔的功放用; 默认不开。
- CTRL.EN = 0 时 BCLK / LRCK / DOUT 停在 0 / 1 / 0; MAX98357A 没有 BCLK 会自己静音。

## 声道

每个采样 (1/48000 秒) 每个声道走一步:

- 相位 (16 位) += FREQ。频率 = FREQ × 48000 / 65536 Hz, 分辨率约 0.73 Hz, 最高 24 kHz。C 用 `AUDIO_HZ(440)` 换算。
- 方波 (声道 0~2): 相位高 8 位 < DUTY 时输出 +幅度, 否则 −幅度。DUTY = 128 是 50%, 32 是 12.5% (尖)。
- 噪声 (声道 3): 相位每溢出一次, 15 位 LFSR 走一步 (同 NES: 反馈 = bit0 ⊕ bit1, 短周期时 bit0 ⊕ bit6), 最低位定正负。
  FREQ 越大越 "嘶"; 短周期 (DUTY bit0 = 1) 是 93 步一轮, 有音高的金属声。
- 幅度 = VOL × 32。四个声道最大 4 × 255 × 32 = 32640, 相加不会溢出, 不用限幅。FREQ 或 VOL 为 0 的声道输出 0。
- LEN 不为 0 时每个采样减 1, 减到 0 的那个采样把 VOL 清 0: 音效写一次就放完自己停, 不用 CPU 计时。
  LEN 最大 65535 (1.365 秒)。C 用 `AUDIO_MS(100)` 换算。
- 寄存器改了以后 1~2 个采样 (约 40 µs) 才到输出。

## 寄存器 (基址 0x4000_8000, 都是 32 位)

| 偏移 | 名字 | 说明 |
|---|---|---|
| 0x00 | CTRL | bit0 EN 打开 (复位 0); bit1 EXACT 整数分频 |
| 0x04 | SAMPLES | 只读, 打开以来出了几个采样 (C 可以拿它计时) |
| 0x08 | MIX | 只读, 最近一个混好的样本, 有符号 16 位符号扩展 |
| 0x10 + 0x10·n | FREQ[n] | [15:0] 相位增量; 0 = 不响 |
| 0x14 + 0x10·n | VOL[n] | [7:0] 音量; 0 = 不响 |
| 0x18 + 0x10·n | DUTY[n] | 方波 [7:0] 占空比 / 256, 复位 128; 噪声 (n = 3) bit0 短周期 |
| 0x1C + 0x10·n | LEN[n] | [15:0] 再响几个采样就把 VOL 清 0; 0 = 一直响 |

n = 0~2 方波, 3 噪声。其他地址读 0, 写丢弃。

## C 接口

`sw/drivers/audio.h` (寄存器) 和 `sw/bsp/board_audio.h` (本板功放接在哪):

```c
#include "board_audio.h"

board_audio_init();                                                    /* 打开外设, 接好功放的脚 */
audio_beep(AUDIO_SQUARE0, AUDIO_HZ(880), 120, AUDIO_MS(80));           /* 880 Hz 响 80 ms 自己停 */
audio_tone(AUDIO_SQUARE1, AUDIO_HZ(220), 60, AUDIO_DUTY(25));          /* 一直响, audio_off 停 */
audio_noise(AUDIO_HZ(12000), 100, 0, AUDIO_MS(200));                   /* 爆炸声 */
```

mes2l100hp 上 `board_audio_init` 把 BCLK / LRCK / DOUT 接到 GameShield 的 AMP_BCLK / AMP_LRCK / AMP_DIN (MAX98357A 模块 J3),
AMP_SD 当普通 GPIO 拉高开机 (SD 直接拉到 3.3 V 时 MAX98357A 只放左声道; 两个声道样本一样, 没关系)。
其他板没有功放, 只打开外设。参数是常量时 `AUDIO_HZ` / `AUDIO_MS` 编译期算好 (rv32i 没有乘除法)。

## 测试

- `tests/audio/audio_tb.sv`: 测试台当 I2S 接收端解码, 核对槽格式、采样率 (4800 帧正好 0.1 s)、BCLK 周期、
  方波频率 / 音量 / 占空比、两个声道相加、噪声 (长周期不重复, 短周期 186 帧一轮)、LEN 自停、EXACT 和关掉后时钟停。
- `tests/soc/audio_check.c` (soc_tb): 寄存器在总线上、三根线经矩阵出得了引脚。

## 以后: HDMI 音频

同一个 I2S 也能送 HDMI 发送芯片 MS7210 (板载, 显示器出声), 这次没接。要接需要:

1. 板级顶层加三个输出口接 MS7210 的 I2S 输入 (spike 用的管脚 SCK = T23, WS = B25, SD = P26, LVCMOS33),
   fdc 加约束; soc_top 把 `i2s_bclk / i2s_lrck / i2s_dout` 引出成端口 (这三根是 MS7210 专用管脚, 不在引脚表里, 不走矩阵)。
2. `ms7210.c` 配音频寄存器 (I2S、48 kHz、16 位) 和 Audio InfoFrame, spike 分支上有现成的。
3. 上板确认 MS7210 吃这个有抖动的 BCLK (spike 是同样做法); 不行就开 EXACT, InfoFrame 照写 48 kHz。
