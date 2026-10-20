# CPU 仿真与板级地址约定

以下地址用于当前 CPU 回归和 RIB SoC：指令 ROM 与数据 RAM 分离，复位入口为 ROM 基址。CPU 扩展能力、测试保留区及验证边界见 [cpu-baseline.md](cpu-baseline.md)。

Architecture:
    RV32I
    little-endian
    ABI = ilp32

Reset vector:
    0x00000000

ROM (instruction):
    0x00000000 - 0x0000ffff
    64 KiB

RAM (data):
    0x10000000 - 0x1000ffff
    64 KiB

Stack:
    initial sp = 0x10010000

MMIO:
    RIB slots s2 (0x20000000) and s3 (0x30000000) are free
    RIB slot s4 (0x40000000) = peripheral bus, 4 KiB per port by addr[15:12]:
        0x40000000 GPIO (pins 0..2 = CS/DC/RST_N, pins 8..15 = led[0..7]; CTRL/DATA/BSRR)
        0x40001000 UART (CTRL/STATUS/BAUD/TXDATA/RXDATA at 0/4/8/C/10)
        0x40002000 SPI  (CR1/CR2/SR/DR at 0/4/8/C)
    CPU/SoC tests reserve RAM word 0x10000000 for completion

Interrupt:
    none

CSR:
    inherited M-mode CSR/trap paths; basic directed tests only

Misaligned access:
    unsupported initially
