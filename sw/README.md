# sw: 运行在 rtl/soc_top 上的 C 程序

分层, 上层仅依赖下层:

```
app/          应用程序, 每个子目录一个程序 (app/<程序>/main.c)
components/   外部芯片驱动, 不碰寄存器. 已有 lcd/: ST7789 / ILI9341, 画点/线/矩形/清屏
bsp/          板级: 主频, delay_ms
drivers/      外设驱动: spi
device/       寄存器定义和基址
startup.S     设栈, 把 .data 初值从 ROM 拷到 RAM, 清 BSS, 调 main
link.ld       ROM 0x0000_0000 放代码和 .data 初值, RAM 0x1000_0000 放数据和栈
```

## 编译

新程序: 建 `sw/app/<程序>/main.c` (目录下所有 .c 一起编译; `test/` 子目录放电脑上跑的逻辑测试)。

上板和仿真用仓库根目录的 `./ama` (`./ama --help`), 如 `./ama run snake`、`./ama sim snake`, 见根目录 README。

## 存储与复位

像单片机一样: ROM 相当于 Flash, RAM 相当于 SRAM。

- `link.ld` 里 `.data > RAM AT > ROM`: 程序按 RAM 地址访问变量, 初值存放在 ROM。
- `startup.S` 每次上电/复位都把初值从 ROM (`_data_load`) 拷到 RAM (`_data_start`~`_data_end`),
  再清零 `.bss`。复位不会恢复片上存储的内容, 所以变量的初值只能靠这一步回来。

## CoreMark

- 算法文件在 `third_party/coremark/`, **一字不改** (CoreMark 规则); 本仓库只写移植层
  `sw/app/coremark/`: `core_portme.c` (用 `cycle` 计数器计时, tick = 时钟周期),
  `core_portme.h` (类型和配置), `ee_printf.c` (官方 printf).
- 编译用 `-march=rv32im_zicsr`, 打开 CPU 已支持的乘除法.

## 注意

- 程序用到外设, 不能在 spike 上运行 (spike 里没有 GPIO/SPI), 只能在 SoC 仿真或板上运行.
- 编译用 `rv32i_zicsr`: `delay_ms` 读 cycle 计数器.
