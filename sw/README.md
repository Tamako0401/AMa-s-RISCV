# sw: 运行在 rtl/soc_top 上的 C 程序

分层, 上层仅依赖下层:

```
app/          应用程序, 每个子目录一个程序 (app/<程序>/main.c)
components/   外部芯片驱动, 不碰寄存器. 已有 lcd/: ST7789 / ILI9341, 画点/线/矩形/清屏
bsp/          板级: 主频, delay_ms, 屏幕接在哪个 SPI 和哪几个 GPIO (bsp.h)
drivers/      外设驱动: spi, gpio
device/       寄存器定义和基址
startup.S     设栈, 把 .data 初值从 ROM 拷到 RAM, 清 BSS, 调 main
link.ld       ROM 0x0000_0000 放代码和 .data 初值, RAM 0x1000_0000 放数据和栈
```

- 屏幕驱动通过 `components/lcd/lcd_io.h` 的 6 个函数访问硬件, 由 `bsp/bsp_lcd.c` 实现.
- 外设地址见 `docs/platform.md`: GPIO 0x4000_0000, UART 0x4000_1000, SPI 0x4000_2000.

## 编译

```
just app            # 默认 lcd_demo
just app <名字>      # 编译 sw/app/<名字>/*.c
```

新程序: 建 `sw/app/<程序>/main.c`

## 存储与复位

像单片机一样: ROM 相当于 Flash, RAM 相当于 SRAM。

- `link.ld` 里 `.data > RAM AT > ROM`: 程序按 RAM 地址访问变量, 初值存放在 ROM。
- `startup.S` 每次上电/复位都把初值从 ROM (`_data_load`) 拷到 RAM (`_data_start`~`_data_end`),
  再清零 `.bss`。复位不会恢复片上存储的内容, 所以变量的初值只能靠这一步回来。
- RAM 不预装任何东西; 上板/仿真只需要 ROM 镜像: `python3 scripts/elf2hex.py <程序.elf> <输出.hex>`。
- 验证: `python3 scripts/test-lcd.py reset_check --tb reset_tb` (程序改掉自己的变量, 复位后检查初值)。

## 仿真点亮

```
python3 scripts/test-lcd.py [程序名]     # 默认 lcd_demo
just app-sim                            # 同上
```

`tests/soc/st7789_model.sv` 挂在 `soc_top` 的**真实 SPI 引脚**上, 从引脚重建
240x320 画面并打印 ASCII 图, 同时核对 COLMOD/MADCTL 和边框、色块、对角线像素.
一屏要搬约 19 万字节(1200 万周期), 所以优先用 verilator, 秒级完成; 没有 verilator
会退回 iverilog, 大约要十几分钟.

仿真构建额外传 `-DSIM_CYCLE_DIV=1000`: 屏幕初始化里的毫秒延时按真实计数要 2600
万拍, 纯仿真跑不动. 该宏默认 1, **不影响实机行为**.

## 注意

- 程序用到外设, **不能在 spike 上运行* (spike 里没有 GPIO/SPI), 只能在 SoC 仿真或板上运行.
- 编译用 `rv32i_zicsr`: `delay_ms` 读 cycle 计数器.
- 尚未上板. 真屏上可能要在 `components/lcd/st7789.c` 的初始化表里调整, 以及spi mode的试.
- `sw/board/` 并不属于本文所描述范围.
