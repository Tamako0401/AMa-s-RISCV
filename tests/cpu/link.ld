OUTPUT_ARCH(riscv)
ENTRY(_start)

/* 哈佛式存储器布局 (与 rib.v 的从设备译码一致):
 *   ROM: 0x0000_0000, 64 KiB  -- rib s0, 只读, 放 .text/.rodata, 也是复位向量
 *   RAM: 0x1000_0000, 64 KiB  -- rib s1, 读写, 放 .data/.bss/栈
 * 每个设备占 addr[31:28] 一个档位(256 MiB 窗口)。
 *
 * 约定: RAM 窗口的第 0 个字 (0x1000_0000) 保留为测试台的"运行结束"信箱,
 * 程序用 sw a0, 0(0x1000_0000) 结束并上报返回值。因此可用 RAM 从 +4 开始。
 */
MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x10000004, LENGTH = 64K - 4
}

_result = 0x10000000;                       /* 结束信箱, 见上 */
_stack_top = 0x10000000 + 64K;              /* 栈从 RAM 窗口顶端向下增长 */

SECTIONS {
    .text : {
        *(.text.init)
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > ROM

    .data : {
        . = ALIGN(4);
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > RAM

    __global_pointer$ = ADDR(.data) + 0x800;

    .bss (NOLOAD) : {
        . = ALIGN(4);
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > RAM

    ASSERT(_bss_end <= _stack_top - 4096, "Keep at least 4 KiB for stack")
}
