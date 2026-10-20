# MES50HP 上板工程

适用随板资料中的 **MES50HP / PGL50H-6IFBG484**，工具实测 PDS 2022.2-SP1-Lite。使用 50 MHz 时钟、片上 RAM、LED、板载 USB-UART 和 GMT024-8p10p-SPI 屏幕（ST7789V，240×320，只写）。

## 下载

`ama fpga program` 调用 PDS 的 `cdt_cfg_shell` 执行 `flash.tcl`: 位流转成 sfc 写进板上 QSPI flash (上电自动加载),
再下载到 FPGA 马上运行; `--once` 执行 `program.tcl`, 只下载到 FPGA。

手册说板上 flash 是 W25Q128JV / GD25Q128 / XT25BF128 之一, `board.toml` 按 W25Q128JV 写 (PDS 里叫 `W25Q128Q`);
是 GD 的改成 `GD25Q128C`; XT25 不在 PDS 的型号表里, 要先在 Fabric Configuration 的 Flash Operator 里添加。

## 引脚依据

参考位置：`E:/2026FPGA创新设计竞赛紫光同创杯资料包/盘古50K开发板资料/盘古50K开发板`。

- `3_Hardware/MES50HP开发板硬件使用手册_1V1.pdf`：印刷页 9 的时钟表、26 的 UART 表、32–33 的 KEY/LED 表。
- `2_Demo/01_led_test.rar`、`02_key_led_test.rar`、`04_uart_test.rar`：核对 FDC、器件与复位极性。示例标注 PDS 2022.1。

屏幕管脚位置取自厂商例程 `6-实验例程Demo-基于盘古50K/8-ADDA+SPI显示实验/display_test.fdc`。屏幕排针从上到下 GND VCC SCL SDA RESET AO CS BL：VCC 接 3.3 V、GND 共地。

以上 I/O 使用 LVCMOS33。没有复制整套厂商 HDL/IP；引脚事实及约束写法来自随板资料，SoC、顶层、固件与系统测试为本仓库新增。

PMOD 按标准的两排插针编号命名：1~4 为 AB6 / AB7 / Y8 / U6，7~10 为 AA6 / Y7 / W9 / T7。手册表 3-13 和原理图使用双排交错编号 1~8；这里按各排顺序换算成标准 PMOD 编号，避免把表中的 9/10（GND）当成 IO。
