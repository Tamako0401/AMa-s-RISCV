# AMa-s-RISCV

2026 全国大学生嵌入式芯片与系统设计竞赛，FPGA 创新设计赛道，紫光同创选题一「基于紫光同创 RISCV 指令集 CPU 设计」。三人团队基于现有开源 CPU 建立可复现的功能基线，再围绕应用做优化。

当前应用方向是带图形输出的嵌入式游戏系统：HDMI 图块 + 精灵显示，用摄像头画面里的颜色标记控制（已上板跟踪红色盒子），另在探索 SuperTux v0.1.3 移植。赛题要求见 [competition.md](docs/competition.md)。现有核保留 IF/ID/EX 组织；取指是预取队列，直连 ROM 的专用读口，访存走 RIB，两者互不阻塞。

总线按 `valid && ready` 接受请求，RIB 同一时刻只有一笔未完成事务，响应允许延后。详细协议和限制见 [CPU 基线](docs/cpu-baseline.md)；地址约定见 [平台文档](docs/platform.md)。

## 改完代码怎么上板

用仓库根目录的 `ama`。它由 [uv](https://docs.astral.sh/uv/) 运行, 第一次会自动装好依赖 (typer、pyserial);
Linux/macOS 直接 `./ama`, Windows 上 `uv run --script ama`。`./ama --help` 看全部命令。
每个命令做什么、规则和代码结构见 [tools/ama/README.md](tools/ama/README.md)。

| 什么时候 | 命令 | 说明 |
| --- | --- | --- |
| 平时改了 C | `./ama run snake` | 编译, 经串口 bootloader 下载到板子运行, 再显示串口输出 (Ctrl+] 退出)。几秒 |
| 只编译 / 只下载 / 只看串口 | `./ama build snake` / `./ama upload snake` / `./ama monitor` | |
| 改了 `rtl/`、`boards/`、`sw/boot/` | `./ama fpga build -b mes50hp` 然后 `./ama fpga program` | 出只带 bootloader 的位流, 写进板上 flash, 上电自动加载。几分钟; `--once` 只下载一次 (断电丢) |
| 程序要特定位流参数 (如相机) | `./ama fpga build -b mes50hp --app camera` 然后 `./ama fpga program -b mes50hp --app camera` | `app.toml` 的 `params` 会改写顶层参数并算进 `hwid`, 不带 `--app` 编出来的位流不能用; 见 [OV7670](docs/ov7670.md) |
| 没有板子 | `./ama sim snake` | sw/app 下的程序跑在 soc_top 上, 窗口显示屏幕和 HDMI 画面, 终端显示串口; 关窗口或 Ctrl+C 结束, 截图在 build/sim/<程序>-lcd.png、-hdmi.png |

- 程序就是 `sw/app/<名字>/`, 目录下的 .c 一起编译。
- 板子按插着的 USB 串口芯片识别 (FT2232 = EGO1, CP2102 = 盘古), 认不出时加 `--board ego1` 或 `--board mes50hp`。
- 下载时会核对板上位流和本地源码的硬件版本号, 对不上会提示先 `fpga build`、`fpga program`。原理见 [bootloader](docs/bootloader.md)。
- 工具不在 PATH 或名字不同时, 参考 `ama.local.toml.example` 写本机配置, `./ama doctor` 核对。盘古的下载用 PDS 的 `cdt_cfg_shell` (Fabric Configuration 的命令行版)。
- 接线见 [boards/ego1/README.md](boards/ego1/README.md)、[boards/mes50hp/README.md](boards/mes50hp/README.md); 引脚怎么分配见 [GPIO 矩阵](docs/gpio-matrix.md)。

## 仓库导航

| 路径 | 内容 |
| --- | --- |
| `rtl/core/`、`rtl/cpu.f` | CPU 核与独立文件清单 |
| `rtl/perips/`、`rtl/utils/`、`rtl/reusable.f` | 外设、通用工具和组件清单 |
| `rtl/nn/` | handnet 加速器 (int8 定点, 权重在片上 ROM) |
| `rtl/soc_top/`、`rtl/soc.f` | 通用 RIB SoC |
| `model/` | 视觉算法的 Python 试验和参考模型 (硬件的标准答案) |
| `experiments/` | 数字逻辑学习实验 |
| `third_party/`、`LICENSES/` | 来源清单、Spike 补丁和适用许可证 |

- [赛题要求与答疑要点](docs/competition.md)
- [CPU 基线与验证边界](docs/cpu-baseline.md)
- [SPI 寄存器](docs/spi.md)
- [离线 Difftest 与已知限制](docs/difftest.md)
- [RTL 来源、授权与接入条件](docs/third-party.md)
- [视频外设 (HDMI, 图块 + 精灵)](docs/video.md)
- [显示扩展方案 (720p、多图层、软硬件分工, 草案)](docs/display-plan.md)
- [新显示 (720p 逐行渲染, 仿真中)](docs/display.md)
- [视觉输入 (HDMI 输入, 缩小, 小窗)](docs/vision.md)
- [OV7670 摄像头 → HDMI (接线、`./ama` 上板、实测结果)](docs/ov7670.md)
- [OV7670 在线调参方案 (UART 实时改寄存器, 设计稿)](docs/ov7670-tuning.md)
- [handnet 加速器 (RTL、寄存器、C 库、量化)](docs/nn.md)
- [徒手手势模型 (数据、标注、训练)](docs/hand-model.md)
- [参考项目: 手势控制游戏、FPGA 手势识别、sprite 引擎](docs/references.md)
- [飞书项目知识库](https://njupt-sast.feishu.cn/wiki/TUxXwMAh3iIraCkTDjxcWd0Tnmh)

## 来源与复用

CPU 主要来源为 [JerryYin777/FPGA_Competition-RISC-V_Processor-in-PGL22G](https://github.com/JerryYin777/FPGA_Competition-RISC-V_Processor-in-PGL22G)，固定提交 `00a3334d7c98f57a6d429a5e18910a7e2e88390b`。已修正取指/访存握手、返回 PC、JALR 和仿真兼容性，并保留适用版权及许可证。具体文件、修改和校验值见 [来源记录](docs/third-party.md) 与 `third_party/tinyriscv-manifest.json`。

参考仓库是旧参赛移植工程，未确认是本届官方参考设计。本仓库采用逐文件授权记录；Apache-2.0 适用文件不代表整库或厂商 IP 统一采用该许可证。比赛对开源复用与贡献披露的要求仍需按本届官方说明核实。
