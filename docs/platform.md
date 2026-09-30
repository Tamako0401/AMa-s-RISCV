# CPU 仿真与板级地址约定

以下地址用于当前 CPU 回归和 RIB SoC：指令 ROM 与数据 RAM 分离，复位入口为 ROM 基址。CPU 扩展能力、测试保留区及验证边界见 [cpu-baseline.md](cpu-baseline.md)。

MES50HP 最小板级 SoC 使用另一套统一 RAM 布局：RAM/复位入口为 `0x80000000`，栈顶为 `0x80010000`，UART 位于 `0x30000000`、GPIO 位于 `0x40000000`；不使用测试完成邮箱，也未接入 SPI。板级完整约定见 [MES50HP 文档](../boards/mes50hp/README.md)。

Architecture:
    RV32I
    little-endian
    ABI = ilp32

Reset vector:
    0x00000000

ROM (instruction):
    0x00000000 - 0x0000ffff
    64 KiB
    read-only

RAM (data):
    0x10000000 - 0x1000ffff
    64 KiB

Stack:
    initial sp = 0x10010000

MMIO:
    RIB SoC SPI: 0x20000000
    RIB SoC GPIO: 0x40000000 (CS/DC/RST_N; CTRL/DATA/BSRR)
    UART slot is not connected in rtl/soc_top/soc_top.v
    CPU/SoC tests reserve RAM word 0x10000000 for completion

Interrupt:
    none

CSR:
    inherited M-mode CSR/trap paths; basic directed tests only

Misaligned access:
    unsupported initially
