# AMa-s-RISCV

2026 全国大学生嵌入式芯片与系统设计竞赛，FPGA 创新设计赛道，紫光同创选题一「基于紫光同创 RISCV 指令集 CPU 设计」。三人团队基于现有开源 CPU 建立可复现的功能基线，再围绕应用做优化。

当前应用方向是带图形输出的嵌入式游戏系统，并探索 SuperTux v0.1.3 移植。屏幕驱动、交互游戏和完整 SuperTux 移植均未完成；最终流水级数和优化方案仍待团队确认。现有核保留 IF/ID/EX 组织，取指采用单笔事务及响应缓冲，是经过修正的功能基线。

## 当前进展

截至 2026-10-01，源码基于 `cf94471`，本次更新复跑了以下功能测试：

| 部分 | 当前实现与验证 | 尚待完成 |
| --- | --- | --- |
| CPU | 完整取指、译码、执行、写回和控制链路；Icarus、ModelSim 各通过 5 个程序 × 3 组延迟配置，15/15 | 官方架构测试、完整异常/异步中断验证、性能评估 |
| 基础组件 | ALU、寄存器堆、存储、GPIO/UART 自检通过；GPIO 支持 BSRR 和响应背压 | UART 仍需响应始终就绪或事务适配，无 FIFO |
| 通用 RIB SoC | ROM/RAM 分离，接入 SPI 与屏幕 GPIO；3 个系统程序通过 | UART 槽位未接入，未做该顶层的 PDS/实机验证 |
| SPI | CR1/CR2/SR/DR 子集，独立收发缓冲；Icarus、ModelSim 通过四种模式 × 八档分频及边界测试 | 屏幕控制器/分辨率核实、驱动、板级接线、真实屏幕验收 |
| MES50HP 最小系统 | 统一 64 KiB RAM + UART/GPIO；配置启动、KEY1 重启、UART 输出/回显及 CPU 控灯仿真通过；PDS 50 MHz 时序及位流构建通过；**实机 LED 验收已通过（用户实测）** | 实机串口验收记录 |
| MES50HP SPI 屏幕 | SPI 已接入板级系统（`0x40002000`），初始化序列对齐 GMT024-8p10p-SPI 厂商例程（ST7789V 240×320）；板级引脚级画面仿真逐像素核对通过，PDS 50 MHz 时序及位流构建通过 | 实机屏幕验收 |
| Difftest | 已有 RTL/Spike 离线提交日志比较入口 | 日志会过滤真实 NOP/MRET 等情况，未比对 store 内容；本次未运行 Spike |

本次（接入 SPI 屏幕后）PDS 映射为 3415 LUT、2301 FF、4 APM、32 DRM；50 MHz 约束全部满足，慢角 setup slack 为 +1.166 ns。该数字对应 LCD 演示固件的位流；报告估算的频率不是实测最高频率。

板卡已购并到货，当前板级工程对应随板资料的 **MES50HP / PGL50H-6IFBG484**。旧 PGL22G 参考工程和远程 PG2L200H 学习实验的器件、引脚、时钟不能直接套用。远程平台尚未适配。

CoreMark、最高工作频率实测、ILA/片上抓波分析、DDR、Cache、动态分支预测、显示 DMA、ADDA 和游戏应用均未完成。仿真通过、时序满足和生成位流分别记录，实机结果仍待验收。

## 两套系统配置

两套系统共用 CPU 核，但顶层、链接脚本和镜像必须配套；不要混用复位地址。

| 项目 | CPU 回归 / 通用 RIB SoC | MES50HP 最小板级系统 |
| --- | --- | --- |
| 顶层 | `tinyriscv_core` / `soc_top` | `mes50hp_top` → `minimal_soc` |
| 复位 PC | `0x00000000` | `0x80000000`，顶层显式覆盖 |
| 指令/数据存储 | 64 KiB ROM `0x00000000`；64 KiB RAM `0x10000000` | 统一 64 KiB RAM `0x80000000` |
| 栈顶 | `0x10010000` | `0x80010000` |
| SPI | RIB SoC：`0x40002000` | `0x40002000`，只接屏幕，MISO 接地 |
| UART | RIB SoC 的 s3 槽位未接入 | `0x30000000` |
| GPIO | RIB SoC：`0x40000000`；bit0/1/2 为 CS_N/DC/RST_N，bit8~15 为 LED | `0x40000000`；位分配与 RIB SoC 相同 |
| 链接脚本 | `tests/cpu/link.ld`、`sw/link.ld` | `sw/board/link.ld` |
| 测试完成标志 | RAM 首字 `0x10000000`，不是正式外设 | UART `AMA CPU PASS`，无测试邮箱 |

总线按 `valid && ready` 接受请求，每个 CPU 端口最多一笔未完成事务，响应允许延后。详细协议和限制见 [CPU 基线](docs/cpu-baseline.md)；地址约定见 [平台文档](docs/platform.md)。

## 改完代码怎么上板

用仓库根目录的 `ama`。它由 [uv](https://docs.astral.sh/uv/) 运行, 第一次会自动装好依赖 (typer、pyserial);
Linux/macOS 直接 `./ama`, Windows 上 `uv run --script ama`。`./ama --help` 看全部命令。

| 什么时候 | 命令 | 说明 |
| --- | --- | --- |
| 平时改了 C | `./ama run snake` | 编译, 经串口 bootloader 下载到板子运行, 再显示串口输出 (Ctrl+] 退出)。几秒 |
| 只编译 / 只下载 / 只看串口 | `./ama build snake` / `./ama upload snake` / `./ama monitor` | |
| 没有板子 | `./ama sim snake` | 程序跑在 soc_top + 屏幕模型上, 测试台核对画面, 打印 PASS/FAIL (只有带测试台的程序能跑) |
| 改了 `rtl/`、`boards/`、`sw/boot/` | `./ama fpga build`, `./ama fpga program` | 综合位流 (几分钟) 再烧进 FPGA。位流里固化 bootloader 和一个默认程序; 断电后要重新 program |

- 程序就是 `sw/app/<名字>/`, 目录下的 .c 一起编译。
- 板子按插着的 USB 串口芯片识别 (FT2232 = EGO1, CP2102 = 盘古), 认不出时加 `--board ego1` 或 `--board mes50hp`。
- 下载时会核对板上位流和本地源码的硬件版本号, 对不上会提示先 `fpga build`、`fpga program`。原理见 [bootloader](docs/bootloader.md)。
- Vivado/PDS 不在 PATH 时, 参考 `ama.local.toml.example` 写本机配置。盘古的下载器只能在 PDS 图形界面里用, `fpga program` 会告诉你选哪个文件。
- 接线见 [boards/ego1/README.md](boards/ego1/README.md)、[boards/mes50hp/README.md](boards/mes50hp/README.md); 引脚怎么分配见 [GPIO 矩阵](docs/gpio-matrix.md)。

## 运行与构建

在仓库根目录执行。需要 Python 3、Icarus Verilog 的 `iverilog/vvp`；CPU、SoC 和板级固件还需要支持 RISC-V 的 `clang`、`ld.lld`、`llvm-objcopy`，均须在 PATH。

| 目的 | 命令 | 输出目录 |
| --- | --- | --- |
| 组件自检 | `nu --no-config-file scripts/test-reusable.nu` | `build/reusable/` |
| CPU 完整回归 | `nu --no-config-file scripts/test-cpu.nu` | `build/cpu/` |
| CPU ModelSim 回归 | `nu --no-config-file scripts/test-cpu.nu --modelsim` | `build/cpu/modelsim/` |
| SPI 与 GPIO/UART ModelSim 测试 | `nu --no-config-file scripts/test-spi.nu --modelsim` | `build/spi/modelsim/` |
| 通用 SoC 回归 | `python scripts/test-soc.py` | `build/soc/` |
| 板级固件与系统仿真 | `python scripts/build-board.py --simulate` | `build/mes50hp/` |
| 板级仿真与 PDS 全流程 | `python scripts/build-board.py --simulate --pds` | `build/mes50hp/` |
| 板级 SPI 屏幕固件、仿真与位流 | `python scripts/build-board.py --lcd --simulate --pds` | `build/mes50hp/` |

Nu 不在 PATH 时使用已安装的 `nu.exe` 完整路径。ModelSim 额外需要 `vlib/vmap/vlog/vsim`。CPU 入口支持 `--quick` 和 `--vcd`。默认 PDS 为 `C:/pango/PDS_2022.2-SP1-Lite/bin/pds_shell.exe`；其他安装路径设置 `$env.PDS_SHELL`。

GitHub Actions(`.github/workflows/ci.yml`)在推送和 PR 时自动运行 Icarus/Verilator 验收：组件自检、CPU 回归、SPI 引脚时序、SoC 回归、LCD 演示仿真和板级固件/系统仿真。ModelSim、PDS 布局布线和实机验收依赖本地授权工具和硬件，不在 CI 范围内。

MES50HP 工程生成到 `build/mes50hp/build.pds`，SRAM 配置文件为 `build/mes50hp/generate_bitstream/mes50hp_top.sbit`。PDS 必须从生成目录启动；更改固件或 RTL 后重新构建，并核对 `build-manifest.json` 中的源码、镜像、位流和时序报告校验值。`invalid-first-run/` 是初始化镜像未加载的诊断存档，不能用于下载。所有 `build/` 生成物均被 Git 忽略，需要在本机构建。

实机验收：串口设为 **115200 / 8N1 / 无流控**，打开串口后按 KEY1；观察 `AMA CPU PASS`、CPU 驱动的 LED 移动图案；关闭本地回显并发送单个 `Z`，核对回显，再按 KEY1 验证重启。完整接线、引脚和下载步骤见 [板级文档](boards/mes50hp/README.md)。

当前自动回归用 LLVM 生成 RV32 ELF。正式测评还需对齐赛题指定的 `riscv32-unknown-elf-gcc` 和 CoreMark v1.0，设置迭代数并运行不少于 10 秒，不能以本地自检代替跑分。

## 仓库导航

| 路径 | 内容 |
| --- | --- |
| `rtl/core/`、`rtl/cpu.f` | CPU 核与独立文件清单 |
| `rtl/perips/`、`rtl/utils/`、`rtl/reusable.f` | 外设、通用工具和组件清单 |
| `rtl/soc_top/`、`rtl/soc.f` | 通用 RIB SoC |
| `rtl/soc/`、`boards/mes50hp/`、`sw/board/` | MES50HP 最小系统、引脚约束和固件 |
| `tests/`、`scripts/` | 自检测试台、程序、构建与回归入口 |
| `experiments/` | 数字逻辑学习实验 |
| `third_party/`、`LICENSES/` | 来源清单、Spike 补丁和适用许可证 |

- [CPU 基线与验证边界](docs/cpu-baseline.md)
- [SPI 寄存器、GPIO 控屏与接口迁移](docs/spi.md)
- [离线 Difftest 与已知限制](docs/difftest.md)
- [RTL 来源、授权与接入条件](docs/third-party.md)
- [飞书项目知识库](https://njupt-sast.feishu.cn/wiki/TUxXwMAh3iIraCkTDjxcWd0Tnmh)

## 接下来做什么

1. 补齐 MES50HP 的 UART、回显和 KEY1 实机验收记录（LED 已由用户实测通过），记录源码版本、镜像、时钟及现象。
2. 完成 GMT024-8p10p-SPI 屏幕（ST7789V，240×320，3.3 V）的实机接线与画面验收；驱动、初始化序列、板级集成和引脚级仿真已完成。
3. 接入可信计时与 CoreMark，建立性能、资源和时序基线，再根据应用测量决定流水、显示 FIFO/DMA 或访存优化。
4. 团队确认最终流水级数、分工、应用范围及交付计划，完善片上抓波和性能分析报告。

以上为推进顺序，五级流水和完整 SuperTux 移植尚未定为已确认的实现方案。

## 来源与复用

CPU 主要来源为 [JerryYin777/FPGA_Competition-RISC-V_Processor-in-PGL22G](https://github.com/JerryYin777/FPGA_Competition-RISC-V_Processor-in-PGL22G)，固定提交 `00a3334d7c98f57a6d429a5e18910a7e2e88390b`。已修正取指/访存握手、返回 PC、JALR 和仿真兼容性，并保留适用版权及许可证。具体文件、修改和校验值见 [来源记录](docs/third-party.md) 与 `third_party/tinyriscv-manifest.json`。

参考仓库是旧参赛移植工程，未确认是本届官方参考设计。本仓库采用逐文件授权记录；Apache-2.0 适用文件不代表整库或厂商 IP 统一采用该许可证。比赛对开源复用与贡献披露的要求仍需按本届官方说明核实。
