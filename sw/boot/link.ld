OUTPUT_ARCH(riscv)
ENTRY(_start)
INCLUDE sw/memory.ld
MEMORY {
    ROM (rx) : ORIGIN = _boot_start, LENGTH = _boot_size
    RAM (rw) : ORIGIN = 0x1000FC00, LENGTH = 1K
}
_stack_top = ORIGIN(RAM) + LENGTH(RAM);
SECTIONS {
    .text : { KEEP(*(.text.init)) *(.text .text.*) *(.rodata .rodata.*) } > ROM
    .data : { *(.data .data.*) *(.sdata .sdata.*) } > RAM AT > ROM
    .bss (NOLOAD) : { *(.bss .bss.*) *(.sbss .sbss.*) } > RAM
}
