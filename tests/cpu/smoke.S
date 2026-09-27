/* Local self-checking RV32I program; s11 identifies a failing stage. */
.section .text.init
.globl _start
_start:
    li s11, 2
    li t0, 7
    addi t1, t0, 5
    add t2, t1, t0
    li t3, 19
    bne t2, t3, fail
    li s11, 3
    la s0, scratch
    li t0, 0x89abcdef
    sw t0, 0(s0)
    lw t1, 0(s0)
    bne t0, t1, fail
    lb t1, 0(s0)
    li t2, -17
    bne t1, t2, fail
    lbu t1, 0(s0)
    li t2, 239
    bne t1, t2, fail
    lh t1, 2(s0)
    li t2, -30293
    bne t1, t2, fail
    lhu t1, 2(s0)
    li t2, 0x89ab
    bne t1, t2, fail
    li t0, 0x12
    sb t0, 1(s0)
    li t0, 0x7654
    sh t0, 2(s0)
    lw t1, 0(s0)
    li t2, 0x765412ef
    bne t1, t2, fail
    li s11, 4
    li t0, 10
    li t1, 0
1:  add t1, t1, t0
    addi t0, t0, -1
    bnez t0, 1b
    li t2, 55
    bne t1, t2, fail
    li s11, 5
    jal ra, subroutine
return_here:
    li t2, 77
    bne a0, t2, fail
    la t0, indirect
    ori t0, t0, 1
    jalr ra, 0(t0)  /* odd source address must clear bit zero */
indirect_return:
    li t2, 88
    bne a0, t2, fail
    li s11, 6
    j after_poison
    sw zero, 0(s0) /* wrong-path memory side effect must never occur */
after_poison:
    lw t1, 0(s0)
    li t2, 0x765412ef
    bne t1, t2, fail
    addi zero, zero, 7
    bnez zero, fail
    fence
    li a0, 1
    j finish
subroutine:
    la t0, return_here
    bne ra, t0, fail
    li a0, 77
    ret
indirect:
    la t0, indirect_return
    bne ra, t0, fail
    li a0, 88
    ret
fail:
    mv a0, s11
finish:
    li t0, 0x10000000
    sw a0, 0(t0)
1:  j 1b
.section .data
.balign 4
scratch: .word 0
