# selftest: 板级自检

`ama run selftest`。一次看全 CPU、内存、屏幕、按键、LED、串口是否正常;
两块板通用, 板子差异在 `boards/<板>/`。

## 上电后依次做什么

1. **CPU 和内存** (`cpu_test.c`): 依次检查, 第一个不对的项返回它的编号:

   | 编号 | 检查 | 不对说明 |
   | --- | --- | --- |
   | 2 | `.data` 变量有初值 | startup.S 没把初值从 ROM 拷到 RAM |
   | 3 | `.bss` 变量为 0 | startup.S 没清 BSS |
   | 4 | 写 64 个字再读回 | RAM 读写 |
   | 5 | 栈上数组求和 | 栈、函数调用 |
   | 6 | 按字节、半字写同一个字 | 字节使能 (sel) |

   通过: 串口打印 `AMA CPU PASS`。失败: 打印 `AMA CPU FAIL <编号>`, LED 最高位亮、低位显示编号, 停在这里。
2. **屏幕**: 经 `shield_lcd_init()` 点亮板上插的屏, 画测试图: 白边框、绿对角线、红绿蓝三个色块,
   左下角每个按键一个灰色方块。
3. **循环**:
   - LED 每 0.5 秒流水一格 (说明 CPU 还在跑);
   - 串口收到什么就回什么;
   - 按键按下: 对应方块变白, 串口打印 `KEY DOWN <号>`; 松开变灰, 打印 `KEY UP <号>`。

## 看哪里

| 现象 | 说明 |
| --- | --- |
| 串口什么都没有 | 位流、时钟、串口线; 先 `ama monitor` 再按复位 |
| `AMA CPU FAIL n` | 见上表 |
| 屏幕不亮 / 花屏 | 屏的接线 (`sw/bsp/shield_lcd.h`)、SPI |
| 方块不随按键变 | 按键表 (`boards/<板>/app_board.c`) |

## 文件

| 文件 | 内容 |
| --- | --- |
| `main.c` | 上面三步 |
| `cpu_test.c` | CPU 和内存检查 |
| `boards/<板>/app_board.{h,c}` | 本板的 LED 表、按键表、按键方块在屏上的位置 |

## 测试

- `tests/soc/lcd_tb.sv`: 仿真里逐点核对测试图 (`ama test tests/soc/lcd_tb.sv`)。
- `tests/board/`: 板级测试台都用 selftest 作为默认程序。
- 不用板子看效果: `ama sim selftest`。仿真里写 `tohost = 1` 表示画完 (上板没人读, 无害)。
