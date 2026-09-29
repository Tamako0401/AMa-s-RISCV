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
    none for v0

Interrupt:
    none

CSR:
    none required initially

Misaligned access:
    unsupported initially