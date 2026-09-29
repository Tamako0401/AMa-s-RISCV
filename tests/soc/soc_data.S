/* SoC 级测试 2: 验证 RAM 初值(.data)在 SoC 上被正确载入和读取。

   与 soc_smoke.S 不同, 本程序依赖已初始化的 .data, 所以测试台必须把
   RAM 镜像(+ram=)也预载进 soc_top 的 u_ram (实机上由 ram.v 的
   RAM_INIT_FILE 参数在综合时写入存储初值)。

   结束时把 a0 写到 0x1000_0000, 即测试台约定的"结果信箱"(1 = 通过)。 */
.section .text.init
.globl _start
_start:
    /* 读第一个已初始化变量 */
    la      t0, magic
    lw      t1, 0(t0)
    li      t2, 0x12345678
    bne     t1, t2, fail

    /* 读第二个, 顺便确认两个变量没有互相串扰 */
    la      t0, counter
    lw      t1, 0(t0)
    li      t2, 0xA5A5A5A5
    bne     t1, t2, fail

    /* 再写回去, 确认 RAM 的读、写通路都通 */
    li      t1, 0xC0FFEE00
    sw      t1, 0(t0)
    lw      t2, 0(t0)
    bne     t2, t1, fail

    li      a0, 1
    j       finish
fail:
    li      a0, 0
finish:
    li      t0, 0x10000000
    sw      a0, 0(t0)           /* 结果信箱 */
1:  j       1b

.section .data
.balign 4
magic:   .word 0x12345678
counter: .word 0xA5A5A5A5
