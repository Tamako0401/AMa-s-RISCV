# LCD (GMT024-8p, ST7789V) 引脚约束核对报告

日期: 2026-10-08 · 结论: **引脚约束已存在且与厂商资料完全一致, 本次为核对验证, 未做修改。**

## 概念澄清

约束的对象不是"CPU 的引脚"。CPU 是 FPGA 内部的软核, 它到屏幕的通路是:

```
软核 CPU → SPI 外设 (rtl/perips/spi.v) → 顶层端口 (boards/mes50hp/mes50hp_top.v)
        → FDC 约束绑定到 PGL50H 物理引脚 → ADDA 扩展包排座 → GMT024 屏幕排针
```

FDC 约束做的事情是把顶层端口名绑定到 FPGA 的物理焊盘。屏幕与板卡在硬件上早已连线固定,
约束只是"告诉工具用哪个焊盘", 必须与原理图/厂商 Demo 一致, 否则信号会从错误的引脚出去。

## 约束来源与核对结果

来源: 厂商 Demo `ADDA模块资料/6-实验例程Demo-基于盘古50K/8-ADDA+SPI显示实验/display_test.fdc`
及模块原理图 `ADDA模块资料/3-SPI显示屏硬件手册/GMT024-8p电路原理图.pdf` (8 针排座: GND/RES/SCL/DC/CS/SDA/V3.3/LEDK)。

| 厂商 demo 端口 | 本工程端口 (mes50hp_top.v) | PGL50H 引脚 | 屏幕排针 | 核对 |
|---|---|---|---|---|
| scl | lcd_sck | W8 | SCL | ✅ |
| sda | lcd_mosi | V7 | SDA | ✅ |
| cs  | lcd_cs   | V9 | CS  | ✅ |
| rs  | lcd_dc   | T8 | DC  | ✅ |
| reset | lcd_rst_n | U8 | RES | ✅ |
| bl  | lcd_bl   | U9 | LEDK | ✅ |

六个引脚位置、电平标准 (LVCMOS33)、驱动 (8 mA)、SLEW (SLOW) 均与厂商 demo 一致。
SDO 不接 (屏幕只写), 背光 `lcd_bl` 目前在顶层常拉高 (`assign lcd_bl = 1'b1`), 未占用 SoC 资源。

约束文件: `boards/mes50hp/mes50hp.fdc:81-124`; 输出端口已在 `:128` 统一 `set_false_path`
(无外部同步采样时钟, 与 UART/LED 同一处理)。

## 构建与验收

- 仿真: `python scripts/test-lcd.py` (含 ST7789 行为模型 `tests/soc/st7789_model.sv`)
- 位流: `python scripts/build-board.py --lcd --pds` → `build/mes50hp/generate_bitstream/mes50hp_top.sbit`
- 上板验收: 按 KEY1 后屏幕显示黑底白框 + 绿对角线 + 红/绿/蓝色块, 串口 (115200 8N1) 收到 `AMA LCD PASS`

## 相关软件栈 (已存在)

`sw/board/lcd_main.c` (demo 主程序), `sw/components/lcd/st7789.c` + `lcd.c` (驱动),
`sw/drivers/spi.c`, `sw/bsp/bsp_lcd.c`。
