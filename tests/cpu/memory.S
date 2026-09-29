/* All byte lanes, halfwords, signed negative offsets and ROM write protection. */
.section .text.init
.globl _start
.macro check reg, value
    li t6, \value
    bne \reg, t6, fail
.endm
_start:
    li s11, 2
    la s0, scratch
    sw zero, 0(s0)
    li t0, 0x80
    sb t0, 0(s0)
    li t0, 0xff
    sb t0, 1(s0)
    li t0, 0x7f
    sb t0, 2(s0)
    li t0, 0xab
    sb t0, 3(s0)
    lw t1, 0(s0)
    check t1, 0xab7fff80
    lb t1, 0(s0)
    check t1, -128
    lb t1, 1(s0)
    check t1, -1
    lb t1, 2(s0)
    check t1, 127
    lb t1, 3(s0)
    check t1, -85
    lbu t1, 3(s0)
    check t1, 171
    li s11, 3
    li t0, 0x1234
    sh t0, 0(s0)
    li t0, 0x8000
    sh t0, 2(s0)
    lw t1, 0(s0)
    check t1, 0x80001234
    lh t1, 0(s0)
    check t1, 0x1234
    lh t1, 2(s0)
    check t1, -32768
    lhu t1, 2(s0)
    check t1, 32768
    addi s0, s0, 4
    lw t1, -4(s0)
    check t1, 0x80001234
    li t0, 0x4567
    sh t0, -2(s0)
    lhu t1, -2(s0)
    check t1, 0x4567
    li s11, 4
    la t0, patched
    li t1, 0x00900513 /* addi a0, zero, 9 */
    sw t1, 0(t0)      /* 哈佛: patched 位于 ROM 窗口, 这条写必须被忽略 */
    fence.i
    jal ra, patched
    check a0, 5       /* 仍执行原来的 li a0, 5, 证明 ROM 未被改写 */
    li a0, 1
    j finish
patched:
    li a0, 5
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
