    .section .text.init
    .globl _start
_start:
    la sp, _stack_top
    /* 先开接收, 避免 C 函数保存寄存器时错过 break 后的起始沿。 */
    li t0, 0x40001000
    li t1, 3
    sw t1, 0(t0)
    call main
1:  j 1b
