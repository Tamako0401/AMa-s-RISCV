# MES2L676-100HP 上板工程

适用随板资料中的 **MES2L676-100HP / PG2L100H-6IFBG676**（盘古 100Pro+，Logos2）。器件参数：
66.6k LUT6、155 × 36 Kb 块 RAM、740 个 APM、300 用户 IO（手册 2.1.2.2.1）。
工具实测要求 PDS 2022.2-SP6.4（资料包 5_Software 有安装包和 license 申请模板；
SP1-Lite 里有 Logos2 器件数据，但 license 是否覆盖 PG2L100H 待验证）。

## 与 MES50HP 的差别

- **没有 50 MHz 时钟**：板载 27 MHz 单端（D18）。顶层已内联 `GTP_GPLL` 原语倍频出
  50 MHz 系统时钟（做法同 ego1 的 MMCM），`sw/bsp/bsp.h` 的 `SYSCLK_HZ` 因此是 50 MHz，
  软件、bootloader、`BREAK_CYCLES` 和 MES50HP 完全一致。

## 时钟: GPLL 参数与频率余量

参数语义由厂商例程 `2_Demo/2_5_pll_test`（27 MHz 进、54/81 MHz 出）反推并验证：

```
VCO = clk_in × RATIOM × RATIOF / RATIOI    (datasheet DS04001: VCO 600~1200 MHz, 输入 10~800 MHz)
clkout_i = VCO / RATIO_i                    (RATIO 支持 0.5 步进)
```

本板取 `RATIOI=1, RATIOM=1, RATIOF=25` → VCO 675 MHz，`RATIO0=13.5` → **50 MHz**。
仿真（Verilator）不模拟 PLL：`` `ifdef VERILATOR `` 分支把 clk 旁路、`pll_lock` 恒 1，
测试台直接给 50 MHz——所以测试台和 50K 板跑法一样（无 `CLK_HALF_NS` 覆盖）。

- **要不要 PPLL**：不用。datasheet 里 PPLL 的 VCO 在 1330~2133 MHz、定位是给 DDR 等
  区域时钟；sys 这类全局时钟用 GPLL（分频功能也更多）。板上 6 个 GPLL，够。
- **更高频率行不行**（27 MHz 输入下 VCO=27×M×F、输出=VCO/RATIO0，均受 600~1200 约束）：
  54（VCO 1080/20）、60（810/13.5）、74.25（891/12）、81、90（810/9）、99（891/9）、
  108（1080/10）都可以；**恰好 100 MHz 不可达**（需要 VCO=50 的倍数且 ≤1200，
  与 27 的倍数对不上）。显示扩展计划的每行拍数结论是 50 MHz 已够（最忙一行 72%），
  先不追高；若上板量出 CPU 跟不上再换（改 RATIO 参数 + `SYSCLK_HZ` 即可）。
- **720p 的 74.25 MHz 像素时钟**：50 和 74.25 需要不同 VCO（675 vs 891），一个 GPLL
  出不了两路——到时候用第二个 GPLL（VCO 891、`RATIO0=12`），见
  [docs/display-plan.md](../../docs/display-plan.md) 实施顺序第 1 步。
- `locked` 参与复位（PLL 未锁时不出系统时钟的行为，同 ego1）；锁定时间 datasheet
  上限 200 µs。
- **MS7210/MS7200 共用一条 I2C**（SCL=K22、SDA=K23）和一个复位脚（G25，低有效），
  50K 板上是两条独立总线。`sw/bsp/board_hdmi.h` 按 `PIN_HDMI_RX_SCL` 是否定义自动区分，
  两颗芯片的 I2C 地址不变（0xB2 / 0x56，手册 2.1.3.3）。
- 按键 5 个（本仓库用 KEY0 复位、KEY1~KEY4 进 GPIO 矩阵），LED 8 个，UART 还是 CP2102。
- `sw/app/snake` 还没有本板目录：4 个键对不上它的 7 个逻辑键（上下左右/开局/两个开关），
  移植游戏时再定（输入要改成手势，见 display-plan）。

## 下载

`ama fpga program` 调用 PDS 的 `cdt_cfg_shell` 执行 `flash.tcl`（位流转 sfc 写进板上 QSPI flash
再下载到 FPGA）或 `program.tcl`（只下载）。板上 flash 是 **2 片 W25Q128JV**（手册 2.1.2.2.7），
`board.toml` 暂按单片 `W25Q128Q` 写；固化前先用 Fabric Configuration 的 Scan Outer Flash
看板子报什么型号（可能是 x8 双片模式，型号名不同，届时改 `board.toml` 的 `flash`）。
和 MES50HP 的串口芯片同为 CP2102，自动识别分不出是哪块盘古——下载数据/开终端要带
`-b mes2l100hp`，或在 `ama.local.toml` 写 `board = "mes2l100hp"`。

## 引脚依据

参考位置：`F:/2026FPGA创新设计竞赛紫光同创杯资料包/盘古100Pro+开发板（MES2L676-100HP）配套资料`。

- `1_Demo_document/实验例程说明篇/教程1_硬件实验指导手册_盘古676系列100Pro+开发板.pdf`
  （PDF 页 = 印刷页 + 4）：2.1.2.2.3.2 的 27 MHz 时钟表、2.1.3.2.5 的 UART 表、
  2.1.3.4.1/2 的 KEY/LED 表、2.1.3.3.1/2 的 HDMI 输入/输出表。
- `2_Demo/4_1_led_test.rar`：核对 FDC 写法、器件字符串（`Logos2 / PG2L100H / -6 / FBG676`）、
  下载器为 USB Cable II。
- 以上 I/O 均为 LVCMOS33、3.3V bank（LED 在 L3，HDMI TX 在 L5、RX 在 L4）。没有复制厂商 HDL/IP。

## 扩展脚（LCD / EXP）怎么选的

板上没有 50K 那样的 J8 排针和 PMOD，外部 IO 走核心板 J1~J4 扩展座（手册 2.1.2.2.8）。
把 J1~J4 表和底板外设（HDMI、UART、LED、KEY、EEPROM、SD、网口、PCIe、JTAG）的管脚逐一对照后，
在 J3 上选了一排未被占用、固定 3.3V 的 L4 bank 脚：

| 本仓库名字 | FPGA 脚 | J3 排针 |
| --- | --- | --- |
| LCD_SCK | E26 | 6 |
| LCD_DC | G26 | 9 |
| LCD_MOSI | H26 | 7 |
| LCD_BL | D25 | 13 |
| LCD_CS | D26 | 8 |
| EXP1 | K18 | 49 (SIO_L4_00) |
| LCD_RST | E25 | 10 |
| EXP2 | L19 | 50 (SIO_L4_01) |

刻意避开：J3-3/5（J25/J26，VS1/VS0 疑似配置采样脚）、J3-4/11/12（G25/G24/F24 已被复位和 PCIe 占）、
J1/J4 的 R5/R6 bank（1.5V）和 L6/L7 bank（电压由 VADJ 跳线 J20/J24 决定，不是固定 3.3V）。
屏幕排线从上到下 GND VCC SCK/MOSI 等对应 `sw/bsp/shield_lcd.h`（ST7789 240x320）。
