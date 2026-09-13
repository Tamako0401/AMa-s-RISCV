Architecture:
    RV32I
    little-endian
    ABI = ilp32

Reset vector:
    0x80000000

RAM:
    0x80000000 - 0x8000ffff
    64 KiB

Stack:
    initial sp = 0x80010000

MMIO:
    none for v0

Interrupt:
    none

CSR:
    none required initially

Misaligned access:
    unsupported initially