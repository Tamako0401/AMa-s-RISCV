# sw: 运行在 rtl/soc_top 上的 C 程序

分层, 上层仅依赖下层:

```
app/<程序>/       应用程序: main.c 等; boards/<板>/ 放本板接线 (LED 表、按键表…); test/ 放电脑上跑的测试
components/       外部器件, 不碰寄存器: lcd/ (ST7789 / ST7735 / ILI9341, 画点线矩形)、key/ (按键消抖)、
                  hdmi/ (MS7210 HDMI 发送芯片、MS7200 HDMI 接收芯片)
bsp/              板级: 主频、delay_ms、cycle 计数; <板>_pins.h (ama gen pins 生成); shield_lcd.h (屏插在哪);
                  board_hdmi.h (板上 HDMI 收发芯片: 复位和初始化, 主循环调 board_hdmi_poll)
drivers/          片上外设: io.h (GPIO 矩阵)、uart、spi、video.h (图块 + 精灵, 见 docs/video.md)、
                  i2c (软件 I2C, 引脚经 GPIO 矩阵; 不依赖 bsp, 速度由调用方传入)
device/           amarisc.h: 寄存器定义和基址
startup.S         设栈, 把 .data 初值从 ROM 拷到 RAM, 清 BSS, 调 main
link.ld           app 的链接脚本; 分区见 memory.ld
memory.ld         ROM 分区: app 在前, bootloader 占最后 2K (唯一定义处)
boot/             bootloader: 串口下载 app (协议见 docs/bootloader.md), 固化在位流里
```

| 程序 | 说明 |
| --- | --- |
| hello | 新程序的模板: `ama new <程序>` 复制它 (串口打招呼、画色块、LED 闪) |
| [selftest](app/selftest/README.md) | 板级自检: CPU、内存、屏幕、按键、LED、串口 |
| [snake](app/snake/README.md) | 贪吃蛇, 按键或串口 wasd 控制 |
| [coremark](app/coremark/README.md) | CoreMark 跑分 |
| video_demo | HDMI 出图: 背景 + 弹跳的球 (精灵), 右上角小窗显示 HDMI 输入 |
| game | 两个游戏 (东方式、水果忍者式) 的板上版, 新显示出图, 键盘经串口玩; 只在 mes2l100hp, 见 [game/README.md](../game/README.md) |

**引脚功能只在 components / bsp 里选。** `io_connect_out` / `io_connect_in` (把引脚接到 SPI、UART) 只允许出现在
components 和 bsp 里 (现在只有 `components/lcd/lcd_io.c`), 程序里只用 `io_dir` / `io_write` / `io_read`。
提交比赛前 GPIO 矩阵会换成固定接线, 守住这条, 到时只改这一处。

## 编译

新程序: `./ama new <程序>` (从 `app/hello` 复制)。目录下所有 .c 和 `boards/<板>/` 下的 .c 一起编译。

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
