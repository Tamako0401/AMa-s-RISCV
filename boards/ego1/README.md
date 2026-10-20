# EGO1 哈佛 SoC 上板工程

用于没有 MES50HP 时验证 UART、CoreMark 和屏幕程序; 比赛正式板仍为 MES50HP。
器件 `xc7a35tcsg324-1`, `ego1_top.v` 直接例化 `rtl/soc_top`。
P17 的 100 MHz 经 MMCME2_BASE 和 BUFG 变为 50 MHz, 锁定前保持复位,
因此共用 `sw/` 固件、50 MHz BSP 和 115200 波特率。

外设接线由 `pins.csv` 生成到 `pins.xdc`，`ego1.xdc` 只保留时钟和复位：

| 板上 | 接到 | 说明 |
| --- | --- | --- |
| S0 / S1 / S2 / S3 / S4 | 矩阵 PIN_S0~PIN_S4 | 按下为 1, 矩阵打两拍同步 |
| S6 | 复位 | 按下为低 |

EGO1 版固件带 `-DBOARD_EGO1` 编译，仅选择 `ego1_pins.h`。J5、开关、按键、两组 LED 和 UART 都接入矩阵。

XDC 定义引脚表中的 IO 和 100 MHz 主时钟, 50 MHz 生成时钟由 Vivado 推导;
UART、按键和 LED 没有同步外部接口时序约束, WNS 用来验收内部时序。

## 下载与串口验收

1. USB 接 J6 (UART/JTAG), 打开电源。Vivado Hardware Manager → Open Target → Auto Connect,
   确认器件为 xc7a35t → Program Device, 选择对应目录的 `ego1_top.bit`。成功后 D24 亮;
   首轮只下载 SRAM, 断电后配置丢失。
2. 串口助手选择 FT2232 的 UART 口 (Linux 通常为 `/dev/ttyUSB1`, 以实际枚举为准),
   设置 **115200、8N1、无流控**, 关闭本地回显。先打开串口, 再按下并释放 **S6 (RST)**。

无串口输出时先检查下载状态、串口及参数、S6 和时钟。

## S6 极性与待上板确认

依据课程资料 `EGo1用户手册.pdf` 第 2 页 §5.1 的原理图: FPGA_RESET 经 R28 (4.7 kΩ)
上拉到 3.3 V, S6 按下接地; 第 3 页表格将 FPGA_RESET 对应到 P15。
所以 S6 **松开为高、按下为低**。手册中“默认低、按下高”说的是 S0~S4, 不适用于 S6。

不要按 **S5 (PROG)** 代替 S6, S5 会清除 FPGA 配置。

待上板确认: 用万用表量 P15 的可接触测试点/连线对地电压, 应为松开约 3.3 V、按下约 0 V。
