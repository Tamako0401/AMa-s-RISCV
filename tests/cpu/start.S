.section .text.init
.globl _start
_start:
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, _stack_top
    /* Hardware does not reset x1-x31. Seed callee-saved registers before C
       spills them; the testbench rejects unknown data on the memory bus. */
    li s0, 0
    li s1, 1
    li s2, 2
    li s3, 3
    li s4, 4
    li s5, 5
    li s6, 6
    li s7, 7
    li s8, 8
    li s9, 9
    li s10, 10
    li s11, 11
    la t0, _bss_start
    la t1, _bss_end
1:  bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:  call main
    li t0, 0x10000000
    sw a0, 0(t0)
3:  j 3b
