# MES50HP 上板工程

适用随板资料中的 **MES50HP / PGL50H-6IFBG484**，工具实测 PDS 2022.2-SP1-Lite。使用 50 MHz 时钟、片上 RAM、LED、板载 USB-UART 和 GMT024-8p10p-SPI 屏幕（ST7789V，240×320，只写）。

## HDMI

发送芯片 MS7210 和接收芯片 MS7200 的视频口由 `mes50hp_top` 直连 (`mes50hp.fdc`, 硬件手册表 3-7、3-6),
I2C 和复位经 GPIO 矩阵 (`pins.csv` 的 HDMI_*; 两颗芯片共用复位脚 R17)。
见 [docs/video.md](../../docs/video.md)、[docs/vision.md](../../docs/vision.md)。

### OV7670 External_B 监看

`OV7670_MONITOR=1` 时，External_B/J8 接入 OV7670，并由 50H 输出 640x480 VGA 时序到 HDMI。
可用 `./ama fpga build --board mes50hp --app camera` 构建相机监看位流；该 app 参数只影响此应用，
默认 SoC/HDMI 显示仍不变。摄像头启动配置经 SCCB 自动写入 VGA RGB565 和字节顺序寄存器。

| OV7670 | J8 | FPGA | 用途 |
| --- | ---: | --- | --- |
| SCL / SDA | 21 / 22 | AB9 / Y9 | SCCB，开漏 |
| VS / HS(HREF) | 23 / 24 | V9 / U9 | 输入同步 |
| PLK(PCLK) / XLK(XCLK) | 25 / 26 | U8 / T8 | 像素时钟输入 / 25 MHz 时钟输出 |
| D7..D0 | 27..34 | W8, V7, AB8, AA8, Y6, W6, AB5, Y5 | RGB565 字节流 |
| RET / PWDN | 35 / 36 | AB4 / AA4 | RET 拉高；PWDN 拉低 |
| 3.3V / GND | 39,40 / 37,38 | — | 电源/地 |

监看逻辑假设摄像头输出 640x480、RGB565、MSB 字节先行、HS 高有效；每个方向每 4 点抽样一次，
用一份 **160x120 RGB565** 缓冲在左上角按原尺寸显示，其余像素输出黑；还没收到完整帧时同一区域
显示 8 条彩条。SCCB 用 FPGA 内部上拉（`mes50hp.fdc` 的 `PAP_IO_PULLUP`），不依赖模块上的电阻。
按当前模块说明，RET 在正常工作时拉高。

`OV7670_MONITOR=1` 时 LED1~LED3 是相机状态灯：LED1 亮 = SCCB 初始化完成，LED2 亮 = SCCB 出错，
LED3 亮 = 已经收到过完整一帧。完整用法、`./ama` 上板步骤、上板实测数据和已知问题见
[OV7670 摄像头 → HDMI](../docs/ov7670.md)。

> 注意：PCLK 走的是普通 IO（U8），必须有 `PAP_CLOCK_ASSIGN=GENERAL` +
> `PAP_CLOCK_DEDICATED_ROUTE=FALSE`，否则 place 阶段直接报 `E:Place-0084`。

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
