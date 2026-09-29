/* SoC 级冒烟程序: 验证 core + rib + rom + ram 的端到端通路。

   刻意不使用 .data / .bss / 栈 —— soc_top 里的 ram.v 目前没有初始化文件
   支持, RAM 上电内容是未知值, 所以程序只访问自己刚写过的 RAM 地址。

   走一遍: ibus -> rib -> rom 取指, dbus -> rib -> ram 读写。
   结束时把 a0 写到 0x1000_0000, 即测试台约定的"结果信箱"(1 = 通过)。

   链接脚本用 tests/cpu/link.ld: ROM 0x0000_0000, 可用 RAM 从 0x1000_0004 开始。 */
.section .text.init
.globl _start
_start:
    li      s0, 0x10001000      /* RAM 内的测试区(窗口内, 避开信箱) */
    li      s1, 16              /* 元素个数 */

    /* 第一遍: 逐个写 (0x100 + i) 再读回比较 */
    li      s2, 0
1:  slli    t0, s2, 2
    add     t1, s0, t0
    addi    t2, s2, 0x100
    sw      t2, 0(t1)           /* dbus 写 -> rib -> ram */
    lw      t3, 0(t1)           /* dbus 读 -> rib -> ram */
    bne     t3, t2, fail
    addi    s2, s2, 1
    blt     s2, s1, 1b

    /* 第二遍: 累加, 期望 sum(0x100 .. 0x10f) = 0x1078 */
    li      s2, 0
    li      t4, 0
2:  slli    t0, s2, 2
    add     t1, s0, t0
    lw      t3, 0(t1)
    add     t4, t4, t3
    addi    s2, s2, 1
    blt     s2, s1, 2b
    li      t5, 0x1078
    bne     t4, t5, fail

    /* 字节/半字掩码: 走一遭 dbus 的 sel 通路 */
    li      t0, 0x10002000
    li      t1, 0xFFFFFFFF
    sw      t1, 0(t0)
    li      t1, 0x000000AA
    sb      t1, 0(t0)           /* 只改 byte0 */
    li      t1, 0x0000BB00
    sh      t1, 2(t0)           /* 只改 byte2/byte3 */
    lw      t2, 0(t0)
    li      t3, 0xBB00FFAA
    bne     t2, t3, fail

    li      a0, 1
    j       finish
fail:
    li      a0, 0
finish:
    li      t0, 0x10000000
    sw      a0, 0(t0)           /* 结果信箱 */
3:  j       3b
