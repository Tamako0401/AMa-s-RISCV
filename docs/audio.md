# 声音

`rtl/perips/audio.v`, 映射到 `0x4000_8000`: 3 个方波声道 + 1 个噪声声道 + 1 个 PCM 流声道, 饱和混成 16 位, 标准 I2S 输出。
像老游戏机的声音芯片: CPU 只写频率、音量, 波形由硬件每个采样算一次, 波形声道不用 CPU 喂样本; PCM 由 CPU 喂入, 用一块 512×32 位 RAM。

```
3 方波 + 1 噪声 ─┐
                 ├─> 相加并饱和到 int16 ─> I2S ─┬─> GPIO 矩阵信号 5/6/7 ─> 功放
PCM FIFO × VOL ──┘                            └─> 板级固定引脚 ─> MS7210 HDMI
```

## I2S 输出

- 标准 I2S (Philips): LRCK 低 = 左声道, 左右各 32 位槽, 数据 MSB 先发, LRCK 变后晚一个 BCLK 才发最高位 (一位延迟)。
  BCLK 下降沿换数据, 接收方上升沿采。16 位样本高位对齐, 槽里其余 16 位补 0; 左右声道是同一个样本。
- 采样率 48 kHz, BCLK = 64 × 48 kHz = 3.072 MHz, 不出 MCLK。MAX98357A (I2S 版; B 版是左对齐, 不能用) 直接吃。
- BCLK 由 50 MHz 系统时钟相位累加得到 (每 3125 拍 384 个边沿): 平均频率精确, 每个边沿最多抖一个系统时钟 (20 ns),
  半周期是 8 或 9 拍。方法同 HDMI 音频 spike (`i2s_beep.v`)。
- CTRL.EXACT = 1: 改成系统时钟 16 分频 (BCLK 3.125 MHz, 采样率 48.828 kHz), 没有抖动, 音高都高 1.7%。
  给对 BCLK 抖动挑剔的接收端排查用; 默认不开 (见下方 HDMI 说明)。
- CTRL.EN = 0 时 BCLK / LRCK / DOUT 停在 0 / 1 / 0; MAX98357A 没有 BCLK 会自己静音。

## 声道

每个采样 (1/48000 秒) 每个声道走一步:

- 相位 (16 位) += FREQ。频率 = FREQ × 48000 / 65536 Hz, 分辨率约 0.73 Hz, 最高 24 kHz。C 用 `AUDIO_HZ(440)` 换算。
- 方波 (声道 0~2): 相位高 8 位 < DUTY 时输出 +幅度, 否则 −幅度。DUTY = 128 是 50%, 32 是 12.5% (尖)。
- 噪声 (声道 3): 相位每溢出一次, 15 位 LFSR 走一步 (同 NES: 反馈 = bit0 ⊕ bit1, 短周期时 bit0 ⊕ bit6), 最低位定正负。
  FREQ 越大越 "嘶"; 短周期 (DUTY bit0 = 1) 是 93 步一轮, 有音高的金属声。
- 幅度 = VOL × 32。四个声道最大 4 × 255 × 32 = 32640, 加上 PCM 项后用 18 位有符号数求和, 超过 32767 或低于 −32768 时饱和, 不回绕。FREQ 或 VOL 为 0 的声道输出 0。
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
| 0x50 | PCM_CTRL | bit0 EN (复位 0); [7:4] DIV (复位 3), 0 当 1; EN=0 清空 FIFO |
| 0x54 | PCM_DATA | 只写, 一次推入 4 个有符号 8 位样本, 低字节先播; 只接受整字写 |
| 0x58 | PCM_LEVEL | 只读, [15:0] 剩余样本数 (0~2048); [31:16] 累计欠载次数 (65535 饱和) |
| 0x5C | PCM_VOL | [7:0] 音量 (复位 0), PCM 项 = 有符号样本 × 无符号音量 |

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

## PCM 怎么喂

PCM 与四个波形声道并行。每隔 DIV 个输出帧取一个 int8 样本, 其间保持样本;
DIV=3 时输入 16 kHz, 0/1 都是 48 kHz。播放最后一个样本仍保持满 DIV 帧,
下一次该取样本却没有数据才输出 0, 欠载加 1 (不是每个 48 kHz 帧都加)。
重新有数据后在下一次取样时恢复。修改 DIV 在下一次取样时生效, 修改音量在下一次混音时生效。

FIFO 是同一个 50 MHz 域的 512×32 同步 RAM, 写一字四样本, 读低字节开始逐个取。
LEVEL 是未取出的样本数, 不包括正在保持的当前样本。剩余空间不足 4 时整字丢弃,
即使同拍取样释放空间也按写前 LEVEL 判断; 禁用 PCM 时写 DATA 丢弃。
同拍读写计数净增加 3。欠载计数只在硬件复位时清零, PCM.EN=0 只清 FIFO、当前样本和 DIV 进度。
总 CTRL.EN=0 停输出时钟和取样, 可以保留 PCM.EN=1 预填。

```c
/* 假定 samples 是自己合成/提供的 16 kHz signed int8 数据, 数量为 4 的倍数。 */
audio_enable(0);
audio_pcm_enable(0, 3);
audio_pcm_enable(1, 3);
audio_pcm_volume(128);
int written = audio_pcm_write(samples, count); /* 最多写 2048, 地址可不对齐 */
board_audio_init(); /* 同时送功放和 HDMI; HDMI 还需 board_hdmi_init 配芯片 */
/* 主循环补数据: 用返回值推进游标, 没写下的留到下一帧, 不要忙等。 */
written = audio_pcm_write(samples + cursor, remaining);
cursor += written;
```

`audio_pcm_space()` 返回还能放几个样本; `audio_pcm_write` 自动按空间少写, 向下取 4 的倍数,
返回实际写入数 (n<=0 返回 0)。驱动按单一生产者设计, 不要同时从中断和主循环喂。
游戏的 `core/mix.c` 每帧把背景音乐和最多4个RAM音效饱和混成PCM8, 通过同一PCM声道输出;
FIFO目标800样本 (约50 ms), 不填满。详见 [game/README.md](../game/README.md)。
60 Hz 每帧约喂 267 个样本, 可交替用 264/268 个等凑齐; 2048 样本可缓冲 128 ms。

## HDMI 和功放同时出声

mes2l100hp 把 `soc_top.i2s_bclk / i2s_lrck / i2s_dout` 直接引到 MS7210 的
SCK=T23 / WS=B25 / SD=P26 (顶层 `hdmi_i2s_sck/ws/sd`, LVCMOS33、慢沿)。
同一组信号继续送 GPIO 矩阵 5/6/7, 功放和 HDMI 得到相同的左右声道, 不实例化测试音源。

引脚来源是 `boards/mes2l100hp/pins.csv` 的 `port` 列: 非空表示固定顶层端口,
不占 GPIO 编号。修改后运行 `./ama gen pins mes2l100hp`, 重生成 `pins.fdc`、
`pins_top.vh` 和 `sw/bsp/mes2l100hp_pins.h`; 后两者的矩阵编号保持不变。

`ms7210_init` 在发送部分释放复位之前配置 I2S0、两声道、16 位、48 kHz,
再写 LPCM Audio InfoFrame (类型 0x84、版本 1、长度 10, PB1=0x11、PB2=0x0D,
校验和 0x53)。其他位用读改写保留。音频配置失败仍执行视频释放表,
返回 -1 供调用方报告; 画面初始化流程继续。

寄存器顺序来自提交 `a0176c6`, 位含义参考
[公开 MS7210 Linux 驱动](https://github.com/avmwww/ms7210-linux-driver/blob/main/ms7210.c)
的 `ms7210_misc_audio_pad_in_spdif`、`ms7210_hdmi_tx_shell_set_audio_bits` 等函数;
16 位对应 0x0535[5:4]=01, 与 spike 的 24 位接收设置不同。未取得官方寄存器手册。

默认仍用相位累加: 平均 48 kHz 与芯片 48 kHz 档和音乐数据吻合, 边沿有 20 ns 抖动。
公开驱动选择音频时钟来自管脚, 没有给出允许抖动范围, 因此不能保证板上兼容。
EXACT=1 得到无抖动 BCLK, 但实际输出 48.828125 kHz, PCM DIV=3 变成 16.276 kHz,
音高/播放速度高约 1.7%, 也偏离 HDMI 声明的 48 kHz; 仅作为上板排查选项。
上板 (2026-11-03, 默认相位累加, 不开 EXACT): HDMI 经采集卡录到连续 440 Hz, 左右相同, 峰值 0.373 = 127×96/32768 (样本原样到达);
音阶 C5~G5 频率准确; 同时功放也在响。若必须同时无抖动且准确 48 kHz, 需另做音频时钟方案。

## 测试

- `./ama test tests/audio`: 既有波形测试, 加 PCM I2S 字节序、符号、DIV=0/1/3/15、音量、
  欠载补零和计数饱和、2048 深度、满时丢弃、指针绕回、非整字写忽略、EN=0 清空、正负混音饱和。
- `./ama test tests/soc/soc_tb.sv`: `audio_check.c` 检查 PCM 寄存器/C 接口,
  `+check_audio` 比对 SoC 顶层 I2S 端口与 GPIO 矩阵输出。
- `python tests/audio/ms7210_check.py`: 主机模拟 I2C, 核对 48 kHz / 2 声道 / 16 位配置、
  Audio InfoFrame 校验和、AVI 保留, 32 个音频读写故障位置逐次注错后仍释放视频复位。
- MS7210 锁音、功放和 HDMI 同时出声已上板确认 (见上文 HDMI 一节)。
  PCM 音量 96 的正弦 (rms 0.263) 比 VOL 128 的方波 (rms 0.125) 响约 6.5 dB, 背景音乐可能盖过合成音效, 有素材后按耳朵调。

### 上板

1. `ama run shield_host`: 按 KEY1~4 各响一个方波音, 只验证 I2S -> 功放。
2. `ama run pcm_test` (和 game 同一个位流, `DISPLAY_NEW=1`): 不用 SD 卡, 内存里合成 16 kHz 正弦,
   按游戏的节奏每 1/60 秒补到 800 样本。功放和 HDMI 同时出声; 画面深蓝 = MS7210 配好, 红 = 没应答或音频设置失败。
   串口每秒打印 `rate` (这一秒出了几个采样, 应 48000, EXACT 时 48828)、`level min` (应在 530 左右)、欠载累计和本秒新增 (应 +0)。
   按键: `1` 正弦、`2` 音阶 C5~C6 (听音高)、`3` PCM 正弦和方波每秒交替 (调响度平衡)、`4` 停喂 0.2 秒 (3200 样本减去队列里的 800, 欠载应涨约 2400~2700)、
   `5` 写满 (LEVEL 不超过 2048, 多写一字被丢)、`0` 静音、`e` 切 EXACT (显示器不出声时试)、`+`/`-` PCM 音量。
3. `ama run game`: 串口每 5 秒的 `pcm underrun +N` 应一直 +0。
