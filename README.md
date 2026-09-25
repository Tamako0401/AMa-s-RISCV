# AMa-s-RISCV

2026 FPGA 创新设计赛道，紫光同创选题一 RISC-V CPU 项目。

- 本批次 RTL 来源、接入条件和验证范围：[docs/third-party.md](docs/third-party.md)
- 组件文件清单：[rtl/reusable.f](rtl/reusable.f)
- 现有学习平台约定：[docs/platform.md](docs/platform.md)

当前已移入可独立编译的 ALU、寄存器堆、通用寄存器/RAM/握手组件及 GPIO/UART，尚未组装完整 CPU 或适配远程 FPGA 板卡。已有软件与学习实验保持原状。

用 Nushell 运行组件自检：`nu --no-config-file scripts/test-reusable.nu`。需要 Icarus Verilog 的 `iverilog` 和 `vvp`。测试输出写入 `build/reusable/`。
