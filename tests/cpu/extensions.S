/* Smoke coverage of inherited M/CSR/trap paths, not privileged compliance. */
.section .text.init
.globl _start
.macro check reg, value
    li t6, \value
    bne \reg, t6, fail
.endm
_start:
    li s11, 2
    li t0, -7
    li t1, 3
    mul t2, t0, t1
    check t2, -21
    mulh t2, t0, t1
    check t2, -1
    mulhu t2, t0, t1
    check t2, 2
    mulhsu t2, t0, t1
    check t2, -1
    li s11, 3
    div t2, t0, t1
    check t2, -2
    rem t2, t0, t1
    check t2, -1
    divu t2, t0, t1
    check t2, 1431655763
    remu t2, t0, t1
    check t2, 0
    li s11, 4
    div t2, t0, zero
    check t2, -1
    rem t2, t0, zero
    check t2, -7
    divu t2, t0, zero
    check t2, -1
    remu t2, t0, zero
    check t2, -7
    li t0, 0x80000000
    li t1, -1
    div t2, t0, t1
    check t2, 0x80000000
    rem t2, t0, t1
    check t2, 0
    li s11, 5
    li t0, 0x55
    csrrw t1, mscratch, t0
    check t1, 0
    csrrsi t1, mscratch, 2
    check t1, 0x55
    csrrci t1, mscratch, 1
    check t1, 0x57
    li t0, 0x100
    csrrs t1, mscratch, t0
    check t1, 0x56
    csrrc t1, mscratch, t0
    check t1, 0x156
    csrrwi t1, mscratch, 3
    check t1, 0x56
    csrr t1, mscratch
    check t1, 3
    rdcycle t0
    rdcycle t1
    bgeu t0, t1, fail
    li s11, 6
    la t0, handler
    csrw mtvec, t0
    li s8, 0
    li s9, 11
    la s10, call_site
call_site:
    ecall
    check s8, 1
    li s9, 3
    la s10, break_site
break_site:
    ebreak
    check s8, 2
    /* 7: 乘法的符号/边界组合; 结果紧跟着用, 也连续乘 */
    li s11, 7
    li t0, 0x80000000
    li t1, 0x80000000
    mul t2, t0, t1
    check t2, 0x00000000
    mulh t2, t0, t1
    check t2, 0x40000000
    mulhu t2, t0, t1
    check t2, 0x40000000
    mulhsu t2, t0, t1
    check t2, 0xc0000000
    li t0, 0xffffffff
    li t1, 0xffffffff
    mul t2, t0, t1
    check t2, 0x00000001
    mulh t2, t0, t1
    check t2, 0x00000000
    mulhu t2, t0, t1
    check t2, 0xfffffffe
    mulhsu t2, t0, t1
    check t2, 0xffffffff
    li t0, 0x80000000
    li t1, 0xffffffff
    mul t2, t0, t1
    check t2, 0x80000000
    mulh t2, t0, t1
    check t2, 0x00000000
    mulhu t2, t0, t1
    check t2, 0x7fffffff
    mulhsu t2, t0, t1
    check t2, 0x80000000
    li t0, 0xffffffff
    li t1, 0x80000000
    mul t2, t0, t1
    check t2, 0x80000000
    mulh t2, t0, t1
    check t2, 0x00000000
    mulhu t2, t0, t1
    check t2, 0x7fffffff
    mulhsu t2, t0, t1
    check t2, 0xffffffff
    li t0, 0x7fffffff
    li t1, 0x7fffffff
    mul t2, t0, t1
    check t2, 0x00000001
    mulh t2, t0, t1
    check t2, 0x3fffffff
    mulhu t2, t0, t1
    check t2, 0x3fffffff
    mulhsu t2, t0, t1
    check t2, 0x3fffffff
    li t0, 0x12345678
    li t1, 0x9abcdef0
    mul t2, t0, t1
    check t2, 0x242d2080
    mulh t2, t0, t1
    check t2, 0xf8cc93d6
    mulhu t2, t0, t1
    check t2, 0x0b00ea4e
    mulhsu t2, t0, t1
    check t2, 0x0b00ea4e
    li t0, 0xfedcba98
    li t1, 0x00000003
    mul t2, t0, t1
    check t2, 0xfc962fc8
    mulh t2, t0, t1
    check t2, 0xffffffff
    mulhu t2, t0, t1
    check t2, 0x00000002
    mulhsu t2, t0, t1
    check t2, 0xffffffff
    li t0, 0x00000000
    li t1, 0xffffffff
    mul t2, t0, t1
    check t2, 0x00000000
    mulh t2, t0, t1
    check t2, 0x00000000
    mulhu t2, t0, t1
    check t2, 0x00000000
    mulhsu t2, t0, t1
    check t2, 0x00000000
    li t0, 3
    mul t1, t0, t0
    mul t1, t1, t0
    mulh t2, t1, t1
    add t2, t2, t1
    check t2, 27
    li a0, 1
    j finish
handler:
    csrr t0, mcause
    bne t0, s9, fail
    csrr t0, mepc
    bne t0, s10, fail
    addi t0, t0, 4
    csrw mepc, t0
    addi s8, s8, 1
    mret
fail:
    mv a0, s11
finish:
    li t0, 0x10000000
    sw a0, 0(t0)
1:  j 1b
