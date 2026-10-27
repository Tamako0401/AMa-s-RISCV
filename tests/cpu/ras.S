/* jalr 预测 (RAS 给 ret 的目标, 其它 jalr 用 BTB 记下的上次目标) 猜错时必须被 EX 发现。
 * 每组都循环几遍, 让 BTB/RAS 先学会, 再故意改目标; s11 标出失败的阶段, s10 记执行轨迹。 */
.section .text.init
.globl _start
_start:
    li sp, 0x10010000
    /* 2: 嵌套调用和返回, 比 RAS 深 (6 层 > 4 项), 递归求和 */
    li s11, 2
    li s0, 3
1:  li a0, 6
    call sum_to
    li t0, 21
    bne a0, t0, fail
    addi s0, s0, -1
    bnez s0, 1b
    /* 3: 被调函数改了 ra 再 ret, RAS 的栈顶就是错的 */
    li s11, 3
    li s0, 3
1:  li s10, 0
    call redirect
    addi s10, s10, 1        /* 不应执行: redirect 返回到 back3 */
    j fail
back3:
    li t0, 10
    bne s10, t0, fail
    addi s0, s0, -1
    bnez s0, 1b
    /* 4: 函数指针轮流换目标 (BTB 记着上次的目标, 每次都猜错) */
    li s11, 4
    li s10, 0
    li s0, 6
    la s1, fn_a
    la s2, fn_b
1:  jalr s1
    mv t0, s1
    mv s1, s2
    mv s2, t0
    addi s0, s0, -1
    bnez s0, 1b
    li t0, 0x333            /* 3 次 fn_a (+1) 和 3 次 fn_b (+0x110) */
    bne s10, t0, fail
    /* 5: 跳转表 (jr, 不写 ra): 目标按 0,1,2,0,1,2... 变化 */
    li s11, 5
    li s10, 0
    li s0, 0
    li s2, 0                /* 表下标 0,1,2 循环 */
    la s1, table
1:  slli t1, s2, 2
    add t1, t1, s1
    lw t1, 0(t1)
    addi s2, s2, 1
    li t0, 3
    bne s2, t0, 3f
    li s2, 0
3:  jr t1
case0:
    addi s10, s10, 1
    j 2f
case1:
    addi s10, s10, 0x10
    j 2f
case2:
    addi s10, s10, 0x100
2:  addi s0, s0, 1
    li t0, 7
    bne s0, t0, 1b
    li t0, 0x223            /* 3 次 case0, 2 次 case1, 2 次 case2 */
    bne s10, t0, fail
    /* 6: auipc + jalr 的远调用 (rd = rs1 = ra), 非零 imm */
    li s11, 6
    li s10, 0
    li s0, 4
1:  .option push
    .option norelax
    call far_fn
    .option pop
    addi s0, s0, -1
    bnez s0, 1b
    li t0, 4
    bne s10, t0, fail
    /* 7: 奇数 imm 的 jalr (目标清掉 bit 0, 不预测) 和非零偶数 imm 的 jalr, 隔一次才执行 */
    li s11, 7
    li s10, 0
    li s0, 4
    la s1, fn_a
1:  addi t1, s1, -7
    jalr 7(t1)
    andi t0, s0, 1
    beqz t0, 2f
    addi t1, s1, 8
    jalr -8(t1)
2:  addi s0, s0, -1
    bnez s0, 1b
    li t0, 6                /* 4 + 2 次 fn_a */
    bne s10, t0, fail
    /* 8: 函数尾部 jr 跳到另一个函数 (尾调用), 返回地址仍是最初的调用点 */
    li s11, 8
    li s10, 0
    li s0, 3
1:  call tail_head
    addi s0, s0, -1
    bnez s0, 1b
    li t0, 0x33
    bne s10, t0, fail
    /* 9: 同一条 jalr -8(t1), t1 在 fn_a+8 和 fn_a 之间交替: 第二种情况 rs1 恰好等于上次的目标,
     * 真正的目标却是 fn_a-8。核对时必须比 rs1 与 (预测目标 - imm), 不能直接比 rs1 */
    li s11, 9
    li s10, 0
    li s0, 4
    la s1, fn_a
1:  andi t0, s0, 1
    addi t1, s1, 8
    beqz t0, 2f
    mv t1, s1
2:  jalr -8(t1)
    addi s0, s0, -1
    bnez s0, 1b
    li t0, 0x202            /* 2 次 fn_a, 2 次 fn_a-8 */
    bne s10, t0, fail
    li a0, 1
    j finish
fail:
    mv a0, s11
finish:
    li t0, 0x10000000
    sw a0, 0(t0)
1:  j 1b

/* a0 = 1 + 2 + ... + a0 */
sum_to:
    addi sp, sp, -8
    sw ra, 4(sp)
    sw a0, 0(sp)
    addi a0, a0, -1
    beqz a0, 2f
    call sum_to
2:  lw t0, 0(sp)
    add a0, a0, t0
    lw ra, 4(sp)
    addi sp, sp, 8
    ret

redirect:
    li s10, 10
    la ra, back3
    ret

fn_a_m8:                    /* = fn_a - 8, 见第 9 组 */
    addi s10, s10, 0x100
    ret
fn_a:
    addi s10, s10, 1
    ret
fn_b:
    addi s10, s10, 0x110
    ret

tail_head:
    addi s10, s10, 1
    la t1, tail_body
    jr t1
tail_body:
    addi s10, s10, 0x10
    ret

/* 放远一点, 让 call 必须是 auipc + jalr */
.section .text.far, "ax"
far_fn:
    addi s10, s10, 1
    ret

.section .data
.balign 4
table:
    .word case0
    .word case1
    .word case2
