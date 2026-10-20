OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K }
_stack_top = ORIGIN(RAM) + LENGTH(RAM);
SECTIONS {
    .text : { *(.text.init) *(.text .text.*) *(.rodata .rodata.*) } > RAM
    .data : { . = ALIGN(4); *(.data .data.*) *(.sdata .sdata.*) } > RAM
    __global_pointer$ = ADDR(.data) + 0x800;
    .bss (NOLOAD) : {
        . = ALIGN(4); _bss_start = .;
        *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON)
        . = ALIGN(4); _bss_end = .;
    } > RAM
    ASSERT(_bss_end <= _stack_top - 4096, "Keep at least 4 KiB for stack")
}
