# minimal_soc (存档, 不再构建)

盘古 MES50HP 上第一版上板用的最小 SoC: 统一 64 KiB RAM (0x8000_0000)、UART 0x3000_0000、
旧 GPIO (rtl/perips/gpio.v) 0x4000_0000、SPI 0x4000_2000。正式线已换成 rtl/soc_top + GPIO 矩阵。

这里的文件不进构建、不进 CI, 只供参考。CPU 核仍在 rtl/core/, 核以后改了这里可能编不过。
最后一次能用 `python3 scripts/build-board.py [--lcd] [--simulate] [--pds]` 构建的提交是 b4f21f6。

| 文件 | 原位置 |
|---|---|
| rtl/minimal_soc.v | rtl/soc/ |
| boards/mes50hp_top_minimal_soc.v (模块名原为 mes50hp_top) | boards/mes50hp/mes50hp_top.v |
| boards/mes50hp_minimal_soc.fdc | boards/mes50hp/mes50hp.fdc |
| sw/ (main.c 自检, lcd_main.c 屏幕演示, gpio.h 旧 GPIO 驱动) | sw/board/ |
| tests/board_lcd_tb.sv | tests/board/ |
| tests/board_reset*.{c,sv} (KEY1 后 .data 不恢复的缺陷复现) | tests/directed/ |

rtl/perips/gpio.v 已删, 需要时从 git 历史取。
