/* load 结果晚一拍写回 (exu_mem/gpr_reg 第二个写口) 的相关冒险; s11 标出失败的阶段。
 * 每组都让依赖指令紧跟在 load 后面, 也测隔一条、连续 load 和 load 后改写同一寄存器。 */
.section .text.init
.globl _start
_start:
    la s0, data
    /* 2: load -> ALU 两个源操作数 */
    li s11, 2
    lw t0, 0(s0)
    add t1, t0, t0
    li t2, 0x2468ace0
    bne t1, t2, fail
    lw t0, 4(s0)
    sub t1, zero, t0
    li t2, -5
    bne t1, t2, fail
    /* 3: load -> 分支比较 (rs1 和 rs2) */
    li s11, 3
    lw t0, 4(s0)
    li t1, 5
    lw t2, 4(s0)
    bne t2, t1, fail
    lw t2, 4(s0)
    bne t1, t2, fail
    /* 4: load -> store 的数据和地址 */
    li s11, 4
    lw t0, 0(s0)
    sw t0, 8(s0)
    lw t1, 8(s0)
    li t2, 0x12345670
    bne t1, t2, fail
    lw t3, 12(s0)          /* t3 = data 的地址 */
    sw t1, 0(t3)
    lw t1, 0(s0)
    bne t1, t2, fail
    /* 5: load -> load 地址 (指针追逐) */
    li s11, 5
    lw t0, 12(s0)
    lw t1, 4(t0)
    li t2, 5
    bne t1, t2, fail
    /* 6: 隔一条再用; 连续 load 互不依赖 */
    li s11, 6
    lw t0, 0(s0)
    addi t3, zero, 1
    add t1, t0, t3
    li t2, 0x12345671
    bne t1, t2, fail
    lw t0, 0(s0)
    lw t1, 4(s0)
    add t2, t0, t1
    li t3, 0x12345675
    bne t2, t3, fail
    /* 7: load 之后紧接着改写同一个寄存器, 晚到的 load 结果不能盖掉它 */
    li s11, 7
    lw t0, 0(s0)
    li t0, 99
    li t2, 99
    bne t0, t2, fail
    lw t0, 0(s0)
    addi t0, zero, 42
    nop
    nop
    li t2, 42
    bne t0, t2, fail
    /* 8: 带符号/无符号的字节和半字, 结果紧跟着用 */
    li s11, 8
    lb t0, 16(s0)
    addi t0, t0, 0
    li t2, -128
    bne t0, t2, fail
    lbu t0, 16(s0)
    li t2, 0x80
    bne t0, t2, fail
    lh t0, 18(s0)
    li t2, -2
    bne t0, t2, fail
    lhu t0, 18(s0)
    li t2, 0xfffe
    bne t0, t2, fail
    /* 9: load 到 x0 不写回, 也不让后面停 */
    li s11, 9
    lw zero, 0(s0)
    bnez zero, fail
    /* 10: 循环里 load 后马上用 (BTB 预测跳转 + load 冒险同时出现) */
    li s11, 10
    li t1, 0
    li t3, 4
    mv t4, s0
1:  lw t0, 0(t4)
    add t1, t1, t0
    addi t3, t3, -1
    bnez t3, 1b
    li t2, 0x48d159c0
    bne t1, t2, fail
    li a0, 1
    j finish
fail:
    mv a0, s11
finish:
    li t0, 0x10000000
    sw a0, 0(t0)
1:  j 1b
.section .data
.balign 4
data:
    .word 0x12345670
    .word 5
    .word 0
    .word data
    .word 0xfffe0080
