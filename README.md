# AMa-s-RISCV

2026 FPGA 创新设计赛道，紫光同创选题一 RISC-V CPU 项目。

- 本批次 RTL 来源、接入条件和验证范围：[docs/third-party.md](docs/third-party.md)
- 组件文件清单：[rtl/reusable.f](rtl/reusable.f)
- 完整 CPU 仿真基线与接口：[docs/cpu-baseline.md](docs/cpu-baseline.md)
- MES50HP/PGL50H 实体板最小系统：[boards/mes50hp/README.md](boards/mes50hp/README.md)
- SPI CR1/SR/DR 与屏幕 GPIO：[docs/spi.md](docs/spi.md)
- RIB ↔ AXI 协议桥（接 DDR3 等 AXI 控制器用）：[docs/axi-bridge.md](docs/axi-bridge.md)
- 现有学习平台约定：[docs/platform.md](docs/platform.md)

当前已接入完整 RV32I CPU 功能基线、RIB + ROM/RAM + SPI 的通用 SoC，以及独立的 MES50HP 最小板级系统。CPU 回归与通用 SoC 使用 ROM/RAM 分离布局；MES50HP 最小系统使用统一 RAM，地址和镜像按各自文档配套。尚未适配远程 FPGA 板卡。

MES50HP/PGL50H 最小系统现已完成仿真及 PDS 50 MHz 时序/位流构建，实机结果待核对。构建命令：`python scripts/build-board.py --simulate --pds`，下载与串口验收见板级文档。

用 Nushell 运行组件自检：`nu --no-config-file scripts/test-reusable.nu`。需要 Icarus Verilog 的 `iverilog` 和 `vvp`。测试输出写入 `build/reusable/`。

完整 CPU 回归：`nu --no-config-file scripts/test-cpu.nu`；添加 `--modelsim` 可使用 ModelSim。需要 Python 和 LLVM RISC-V 编译工具，具体依赖见 CPU 基线文档。当前为保守取指的功能基线，尚未进行性能评估、正式 ISA 认证或 PGL50H 上板。

通用 SoC 回归：`python scripts/test-soc.py`，覆盖 RIB、ROM/RAM、SPI 和 GPIO 控屏通路。组件回归包含四种模式、全部分频和独立引脚收发测试；ModelSim 使用 `scripts/test-spi.nu --modelsim`。数字仿真不代表真实屏幕或上板已通过。

LCD 点亮仿真：`python scripts/test-lcd.py`，把 `sw/app/lcd_demo` 真正跑在 RTL SoC 上，`tests/soc/st7789_model.sv` 从 SPI 引脚重建 240x320 画面并核对像素。优先用 verilator（秒级），没有则退回 iverilog（十几分钟）。仿真构建用 `-DSIM_CYCLE_DIV=1000` 缩短屏幕初始化延时，实机行为不变。
