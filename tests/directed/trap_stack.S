.section .text.init
.globl _start
_start:
    li s0, 0x10000000
    li s1, 0                       # 错误位图, 入口失败后仍继续跑 MRET
    la t0, handler
    csrw mtvec, t0
    li t0, 8                       # MIE=1, MPIE=0, 避免旧 MPIE 掩盖错误
    csrw mstatus, t0
    csrr t0, mstatus
    sw t0, 4(s0)
    la t0, ecall_site
    sw t0, 24(s0)
ecall_site:
    ecall
returned:
    csrr t0, mstatus
    sw t0, 12(s0)
    andi t0, t0, 0x88
    li t1, 0x88                    # 返回后 MPIE=1, MIE=1
    beq t0, t1, 1f
    ori s1, s1, 2
1:  sw s1, 0(s0)                  # 0 成功; bit0 入口, bit1 返回, bit2 cause, bit3 mepc
2:  j 2b

.balign 4
handler:
    csrr t0, mstatus
    sw t0, 8(s0)
    andi t0, t0, 0x88
    li t1, 0x80                    # 入口应复制 MIE -> MPIE 并清 MIE
    beq t0, t1, 1f
    ori s1, s1, 1
1:  csrr t0, mcause
    sw t0, 16(s0)
    li t1, 11
    beq t0, t1, 2f
    ori s1, s1, 4
2:  csrr t0, mepc
    sw t0, 20(s0)
    la t1, ecall_site
    beq t0, t1, 3f
    ori s1, s1, 8
3:  addi t0, t0, 4
    csrw mepc, t0
    mret
