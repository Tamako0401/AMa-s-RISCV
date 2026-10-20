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

- 屏幕是插上去的模块, 不属于板子, 不放在 bsp 里: 驱动通过 `components/lcd/lcd_io.h` 访问硬件, 由 `components/lcd/lcd_io.c` 经 GPIO 矩阵实现.
- 外设地址见 `docs/platform.md`: GPIO 0x4000_0000, UART 0x4000_1000, SPI 0x4000_2000.

## 编译

新程序: 建 `sw/app/<程序>/main.c` (目录下所有 .c 一起编译; `test/` 子目录放电脑上跑的逻辑测试)。

上板和仿真用仓库根目录的 `./ama` (`./ama --help`), 如 `./ama run snake`、`./ama sim snake`, 见根目录 README。

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
```

`tests/soc/st7789_model.sv` 挂在 `soc_top` 矩阵的屏幕引脚上, 从引脚重建
240x320 画面并打印 ASCII 图, 同时核对 COLMOD/MADCTL 和边框、色块、对角线像素.
一屏要搬约 19 万字节(1200 万周期), 所以优先用 verilator, 秒级完成; 没有 verilator
会退回 iverilog, 大约要十几分钟.

仿真构建额外传 `-DSIM_CYCLE_DIV=1000`: 屏幕初始化里的毫秒延时按真实计数要 2600
万拍, 纯仿真跑不动. 该宏默认 1, **不影响实机行为**.

## CoreMark

```
python3 scripts/coremark.py [--cc clang] [--iterations 3] [--opt=-O3]  # 仿真: CRC 校验 + CoreMark/MHz
python3 scripts/coremark.py --cc gcc --min-score 0.5       # GCC 仿真并检查性能底线
python3 scripts/build-board.py --harvard --app coremark --cc gcc --pds  # MES50HP 正式报分位流
python3 scripts/build-board.py --board ego1 --harvard --app coremark --cc gcc --vivado  # EGO1 正式报分位流
```

- 算法文件在 `third_party/coremark/`, **一字不改** (CoreMark 规则); 本仓库只写移植层
  `sw/app/coremark/`: `core_portme.c` (用 `cycle` 计数器计时, tick = 时钟周期),
  `core_portme.h` (类型和配置), `ee_printf.c` (官方 printf, 只实现了 `uart_send_char`).
- 编译用 `-march=rv32im_zicsr`, 打开 CPU 已支持的乘除法.
- `--cc` 可选 `clang` (默认) 或 `gcc`; GCC 依次查找 `riscv32-unknown-elf-gcc`、
  `riscv64-unknown-elf-gcc`、`riscv64-elf-gcc`, 都使用 `-mabi=ilp32`.
- `--min-score X` 指定 CoreMark/MHz 底线, CRC 不通过或分数低于底线时以非零退出,
  低分时打印实际值与底线. CI 分别检查 clang 和 GCC, 更换编译器版本后需重新校准底线.
- `--summary <文件>` 追加 Markdown 表格, 记录编译器、选项、CRC、分数、迭代次数和
  Total ticks; CI 传入 `$GITHUB_STEP_SUMMARY`.
- CoreMark/MHz = 迭代次数 × 10⁶ / Total ticks, 与主频无关. 仿真和实机是同一份 RTL,
  周期数相同, 所以**仿真就能算准 CoreMark/MHz**; 仿真跑不满 10 秒, 输出里那句
  "Must execute for at least 10 secs" 忽略即可, 脚本只看 CRC.
- 赛题正式报分用 GCC (`--cc gcc`, 产物目录以 `-gcc` 结尾). 上板版本 `ITERATIONS=0`:
  CoreMark 先试跑, 再自动选够 10 秒的次数. 串口 115200 看 `Correct operation validated` 和 `Iterations/Sec` (整数, 精确值用 Iterations 和
  Total ticks 算: CoreMark = 迭代次数 × 主频 / Total ticks).
- GCC 正式上板成绩 (GCC 16.2, -O2): EGO1 600 次 / 16.7 s, **0.717 CoreMark/MHz** (与仿真一致); MES50HP 待测.

## 注意

- 程序用到外设, **不能在 spike 上运行* (spike 里没有 GPIO/SPI), 只能在 SoC 仿真或板上运行.
- 编译用 `rv32i_zicsr`: `delay_ms` 读 cycle 计数器.
- 尚未上板. 真屏上可能要在 `components/lcd/st7789.c` 的初始化表里调整, 以及spi mode的试.
- `sw/board/` 并不属于本文所描述范围.

