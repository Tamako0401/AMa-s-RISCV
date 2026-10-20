# GPIO 矩阵

目的: 板上所有资源 (扩展口每个插针、按键、开关、LED) 都接进位流, 用哪个、接什么由 C 代码运行时决定。
接新外设或换插针只改 C, 不再改 `.v`/约束、不再综合。思路照搬 ESP32 的 GPIO 矩阵: **任何外设信号可以接到任何引脚**。

```
             FPGA 内部 (矩阵, 运行时可改)                │  电路板 (焊死)
 GPIO 寄存器某一位 ─┐                                    │
 SPI_SCK ───────────┼─→ [FUNC_OUT_SEL[n] 选一个] ─→ 管脚 ─┼─→ J5-1 / LED / ...
 UART_TX ───────────┘                                    │
```

实现在 `rtl/perips/gpio_matrix.v`, 挂在外设子总线第 3 口 `0x4000_3000`。

## 引脚表: 每块板一张

`boards/<板>/pins.csv` 记录电路板上焊死的事实: 丝印名、FPGA 管脚、方向。表的行号就是引脚编号 (从 0 起)。

```
name,    pad,  dir
J5_1,    B16,  inout
...
S0,      R11,  in
SW0,     R1,   in
LD2_0,   K2,   out
UART_TX, T4,   out
UART_RX, N5,   in
```

`scripts/gen-pins.py <板>` 从表生成三份文件 (生成的文件提交进仓库, 不用每次构建都跑):

| 生成的文件 | 内容 |
|---|---|
| `boards/<板>/pins.xdc` 或 `pins.fdc` | 每个管脚的约束, 端口名 `io[编号]` |
| `boards/<板>/pins_top.vh` | 板级顶层用的 `IO_N` (引脚个数) 和每个引脚的方向, 顶层按方向接三态缓冲 / 输入 / 输出 |
| `sw/bsp/<板>_pins.h` | `#define PIN_J5_1 0` 这样的名字, C 只用名字 |

- `inout` 的脚 (扩展口) 用三态缓冲, 可输入可输出。`in` 的脚 (按键、开关) 只能读, `out` 的脚 (LED) 只能写, 方向寄存器对它们无效。
- 所有输入在矩阵里统一打两拍同步, 板级顶层不再自己同步 (复位键除外, 见下)。
- 上电默认: 全部不驱动 (inout 是输入, out 输出 0), 只有控制台串口按默认接好 (见下)。

两块板要列的资源:

- EGO1: J5-1~32、S0~S4、SW0~SW7、DIP0~7、LD2-0~7、LD1-0~7、UART_TX/RX。数码管以后再加。
- 盘古 MES50HP: J8 的 34 个 IO (按插针号)、PMOD J12 的 8 个 IO、KEY2~KEY8、LED1~8、UART_TX/RX。

**复位键不进矩阵**: EGO1 的 S6、盘古的 KEY1 在板级顶层固定接复位 (异步拉低、同步释放, 和现在一样)。
复位必须在程序跑飞或矩阵配错时也能用, 而且复位本身要清空矩阵, 所以不能由矩阵寄存器决定。

## 外设信号

所有外设的对外信号都经过矩阵, 包括控制台串口。

| 编号 | 输出信号 (外设 → 引脚) | 输入信号 (引脚 → 外设) |
|---|---|---|
| 0 | 普通 GPIO | UART_RX |
| 1 | UART_TX | SPI_MISO |
| 2 | SPI_SCK | |
| 3 | SPI_MOSI | |

- 以后加外设就往表里加编号, 寄存器布局不变。
- 片选 CS、屏幕 DC/RST/背光 用普通 GPIO 由软件翻转, 不进表。
- 上电默认: 引脚表里 `UART_TX` 那个脚的 FUNC_OUT_SEL = UART_TX, 输入信号 UART_RX 的 FUNC_IN_SEL = `UART_RX` 那个脚。
  这两个编号由板级顶层作为参数传给 soc_top, 再传给矩阵。所以 bootloader 和串口打印不用配置就能用; 想换脚在 C 里改即可。
- 没接任何引脚的输入信号给空闲电平: UART_RX = 1, SPI_MISO = 0。

## 寄存器 (基址 0x4000_3000, 都是 32 位)

名字照抄 ESP32, 方便对照它的文档。k = 0~3, 即最多 128 个引脚。

| 偏移 | 名字 | 说明 |
|---|---|---|
| 0x000 + 4·k | OUT[k] | 引脚 32k~32k+31 的输出值 (普通 GPIO 模式下有效) |
| 0x010 + 4·k | OUT_W1TS[k] | 只写, 写 1 的位置 1, 其他位不变 |
| 0x020 + 4·k | OUT_W1TC[k] | 只写, 写 1 的位清 0 |
| 0x030 + 4·k | ENABLE[k] | 1 = 输出, 0 = 输入 (普通 GPIO 模式下有效) |
| 0x040 + 4·k | ENABLE_W1TS[k] | 只写 |
| 0x050 + 4·k | ENABLE_W1TC[k] | 只写 |
| 0x060 + 4·k | IN[k] | 只读, 引脚当前电平 (同步后) |
| 0x200 + 4·n | FUNC_OUT_SEL[n] | 引脚 n 输出什么: [7:0] 输出信号编号, 0 = 普通 GPIO |
| 0x400 + 4·s | FUNC_IN_SEL[s] | 输入信号 s 从哪个引脚读: [7:0] 引脚编号, 0xFF = 不接 |

- FUNC_OUT_SEL 选了外设信号以后, 该脚由外设驱动、自动成为输出, ENABLE/OUT 对它无效。
- 一个引脚只有一个输出源; 一个引脚可以同时喂给多个输入信号。
- 超出 IO_N 的引脚: 写入丢弃, 读回 0。

## C 接口 (`sw/drivers/io.h`)

```c
void io_dir(uint32_t pin, uint32_t dir);               /* IO_INPUT / IO_OUTPUT */
void io_write(uint32_t pin, int level);
int  io_read(uint32_t pin);
void io_connect_out(uint32_t pin, uint32_t sig);       /* 外设信号 -> 引脚; SIG_GPIO 恢复普通 GPIO */
void io_connect_in(uint32_t sig, uint32_t pin);        /* 引脚 -> 外设信号 */
```

例: 点亮 LED、读按键

```c
io_dir(PIN_LED1, IO_OUTPUT);
io_write(PIN_LED1, io_read(PIN_KEY2));    /* 按着 KEY2 时 LED1 亮 */
```

外设引脚由用它的驱动自己接, 比如屏幕驱动把 SCK/MOSI 接到 SPI (`io_connect_out`), CS/DC/RST/背光当普通 GPIO 翻转。
