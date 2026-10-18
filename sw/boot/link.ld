OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
    ROM (rx) : ORIGIN = 0xF800, LENGTH = 2K
    RAM (rw) : ORIGIN = 0x1000FC00, LENGTH = 1K
}
_stack_top = ORIGIN(RAM) + LENGTH(RAM);
SECTIONS {
    .text : { *(.text.init) *(.text .text.*) *(.rodata .rodata.*) } > ROM
    .data : { *(.data .data.*) *(.sdata .sdata.*) } > RAM AT > ROM
    .bss (NOLOAD) : { *(.bss .bss.*) *(.sbss .sbss.*) } > RAM
}
