# 上手指南 (队友先看这个)

板子怎么接、怎么开机、游戏怎么玩、想改游戏从哪下手。细节都链到别的文档, 这里只讲够用的。

## 1. 整套东西长什么样

```
 USB 摄像头 ── 电脑 (tools/cam_hdmi.py 把画面转成 HDMI) ──HDMI──> 100HP 的 HDMI 输入
                                                                      │
                          100HP (PG2L100H, RISC-V SoC + 显示 + 手势加速器)
                          ├─ HDMI 输出 ──> 显示器 / 采集卡 (画面 + 声音)
                          ├─ 扩展板 ATK-FMC-EXTIOB 的 J2 ── GameShield HOST 版
                          │      ├─ 星闪模块 (WS63) ~~~~无线~~~~ 手柄
                          │      └─ 功放 MAX98357 + 喇叭
                          ├─ 板载 KEY1~4 (也能玩)
                          ├─ MicroSD 卡槽 J10 (可选: 立绘、背景音乐、音效 AMA.PAK)
                          └─ USB 串口 (CP2102): 下载程序、看日志、电脑键盘/手柄输入

 手柄: 50K (PGL50H) + GameShield PAD 版 (9 个键 + 摇杆) + 星闪模块, 40P 排线连 50K 的 J8
```

游戏、显示、手势识别、声音全在 FPGA 上跑。电脑只做两件事: 把 USB 摄像头画面转成 HDMI 喂给板子 (板子没有摄像头接口),
以及开发时下载程序、看串口。

## 2. 开机

1. **100HP**: 扩展板插在 FMC 上, 扩展板 **J20 跳线在 3V3**; GameShield HOST 版扣在扩展板 J2 上 (方焊盘对 J2 的 1 脚, 挨着 LA00_P 那端)。
   星闪模块插 GameShield 的 U1 座, 功放插 U2 座。HDMI 输出接显示器。
2. 上电。flash 里已经是游戏, 直接进标题画面 (`AMa-s-RISCV  GAME`)。
3. **手柄 (50K)**: 上电即可, 星闪自己连上 (几秒)。标题画面下面那行 `pad: usb  sle  keys` 里 `sle` 变绿 = 手柄连上了。
4. 要用手势: 电脑接 USB 摄像头, HDMI 线从电脑接到 100HP 的 HDMI 输入, 跑
   `uv run --script tools/cam_hdmi.py` (自己找接 FPGA 的那块屏、全屏; `--cam 1` 换摄像头)。游戏左上的小窗出现画面就对了。

`pad:` 那行三个来源: **usb** = 电脑经 USB 串口发的键 (ama monitor), **sle** = 星闪手柄, **keys** = 板载 KEY1~4。
最近 0.5 秒有输入的亮绿。三个可以同时用, 按键取或。

## 3. 怎么玩

两个游戏, 标题画面上下选, A 开始:

- **bullet hell (东方式弹幕)**: 移动躲子弹, 自动射击; A = bomb (清屏); SLOW 按住慢速移动 (精细躲弹)。
- **fruit slicer (水果忍者式)**: 用刀切飞起来的水果, 别碰炸弹。按键玩时方向键移动刀尖, A 沿最近移动的方向冲一刀。

### 按键对照

| 功能 | 手柄 (50K) | 板载按键 (100HP) | 电脑终端 (ama monitor) |
| --- | --- | --- | --- |
| 移动 | 上下左右键 / 摇杆 | — | wasd / 方向键 |
| A (确认 / bomb / 出刀) | A | KEY1 | j / 空格 / 回车 |
| B | B | — | — |
| 慢速 | SLOW | KEY4 | 大写 WASD (Shift) |
| 重开 | RST | KEY3 | r |
| 菜单 (暂停) | MENU | KEY2 | m |

`ama monitor --pad` 会开一个小窗口, 键盘按住/松开都发, 还能接 Xbox 手柄; 小窗里按 m 切成鼠标 (位置 = 画面位置)。

### 菜单 (MENU)

游戏中按 MENU 暂停: `resume` 继续 / `input: < keys | point >` 切输入方式 / `back to title` 回标题。
- **keys**: 按键移动 (默认)。
- **point**: 用手 (摄像头) 或鼠标指位置。东方式里手的位置就是自机, 握拳再张开 = bomb; 水果里手就是刀, 张开手划过去切。

菜单下面还显示鼠标、手 (有没有、握拳/张开) 和 CPU 每帧用了多少拍, 调试时有用。

## 4. 开发环境

需要: [uv](https://docs.astral.sh/uv/) (跑 ama), git, RISC-V GCC, 改硬件时再要 PDS 2022.2-SP6.4。

- 命令都用仓库根目录的 `ama`: Linux/macOS `./ama ...`, **Windows `uv run --script ama ...`**。`ama --help` 看全部, `ama doctor` 查工具装没装好。
- 编译器名字不一样时, 抄 `ama.local.toml.example` 写一份 `ama.local.toml` (不进仓库), 例如
  Windows 用 xPack 的 `riscv-none-elf-gcc` 就写 `riscv32-unknown-elf-gcc = ["riscv-none-elf-gcc"]`。
  PDS 的 `pds_shell` / `cdt_cfg_shell` 不在 PATH 里也在这里写全路径。
- 板子按 USB 串口芯片识别, 100HP 和 50K 都是 CP2102 分不出: 命令后面加 `-b mes2l100hp` 或 `-b mes50hp`,
  或者在 `ama.local.toml` 写 `board = "mes2l100hp"`。

> Windows 上的整套流程 (编译 + 下载) 还没有完整试过; PDS 本来就是 Windows 软件, 编译器和 uv 也都有 Windows 版。碰到问题把报错发群里。

## 5. 改游戏

**只改 C (最常见)**: 不用重新综合, 几秒钟:

```sh
./ama run game -b mes2l100hp --pad    # 编译 + 经串口下载到板子 + 打开手柄小窗; Ctrl+] 退出
```

这样下载的程序断电就没了 (flash 里还是原来那份)。要固化进 flash 才需要 `fpga build` + `fpga program` (十几分钟, 见第 6 节)。

代码在哪:

| 想改什么 | 看哪里 |
| --- | --- |
| 弹幕玩法、难度、子弹 | `game/core/touhou.c` |
| 水果玩法 | `game/core/fruit.c` |
| 标题画面、游戏切换、主循环 | `sw/app/game/main.c` |
| 暂停菜单 | `game/board/menu.c` |
| 按键 / 手柄输入 | `game/board/pad.c`、`pad.h`; 板载键映射 `game/board/local_keys.h` |
| 音效 (合成音色、优先级) | `game/core/sound.c` (新音效: `sound.h` 加枚举, `effects` 表加一行, 事件处 `sound_play`) |
| 图案 / 精灵 | `game/assets/<名字>.png` 存在就用它, 不然用 `game/tools/assets.py` 的占位图 |
| 立绘、背景音乐、wav 音效 | 放进 `game/assets/portraits|bgm|sfx/`, `uv run game/tools/pack.py` 打成 `AMA.PAK`, 拷到 FAT32 卡根目录 |

规矩: `game/core/` 只用整数和静态数组、不用 libc (同一份代码电脑和板子都跑); 画面只能通过 `gfx.h` "填表"。
详细见 [game/README.md](../game/README.md) (画面接口、声音、SD 素材都在里面)。

**电脑上先玩**: `make -C game && game/build/touhou` (要 SDL2; macOS/Linux 试过, Windows 要 MSYS2, 没试过)。
`--bot` 自动玩, `L` 加难度, 鼠标当输入。

**测试**: 改了 `game/` 跑 `./ama test sw/app/game/test` 和 `make -C game check-core check-audio`; 推之前跑全量 `./ama test` (半小时)。

## 6. 改硬件 (RTL) 或者固化进 flash

```sh
./ama fpga build -b mes2l100hp --app game    # PDS 综合, 十几分钟; --app game 把程序固化进位流 (游戏要 DISPLAY_NEW=1, 写在 app.toml)
./ama fpga program --app game                # 写进 flash, 上电自动跑
./ama fpga build -b mes50hp --app shield_pad && ./ama fpga program -b mes50hp --app shield_pad   # 50K 手柄
```

- 100HP 游戏位流时序全部满足 (`All Constraints Met`)。`fpga build` 的布局布线带 `-fix_hold_violation -optimize_multi_corner_timing`:
  PDS 默认只按 fast corner 修保持时间, 以前 slow corner 剩一条 -0.011 ns (CPU 的 PC 到分支预测表)。
- 50K 的手柄程序关掉了手势加速器 (`sw/app/shield_pad/app.toml` 的 `NN = 0`), 否则块 RAM 不够;
  也关掉了串口 break 复位 (`UART_BREAK_RESET = 0`), 否则只插电源时控制台 RX 悬空, 设计一直被压在复位里。

## 7. 硬件细节去哪看

| | |
| --- | --- |
| 100HP 板级、下载、flash 型号坑 | [boards/mes2l100hp/README.md](../boards/mes2l100hp/README.md) |
| 50K 板级 | [boards/mes50hp/README.md](../boards/mes50hp/README.md) |
| 声音 (方波/噪声/PCM、I2S、HDMI 音频) | [audio.md](audio.md) |
| SD 卡、AMA.PAK 格式 | [sd.md](sd.md) |
| HDMI 输入、小窗 | [vision.md](vision.md) |
| 显示硬件 | [display.md](display.md) |
| 手势加速器 handnet | [nn.md](nn.md)、[hand-model.md](hand-model.md) |
| 引脚怎么接到外设 | [gpio-matrix.md](gpio-matrix.md) |
