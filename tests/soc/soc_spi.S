/* SoC 级测试 3: 通过 RIB 读写 SPI 从设备(0x2000_0000)的寄存器。

   rtl/perips/spi.v 的寄存器偏移:
     0x0 CTRL   [0]enable(自清位) [1]CPOL [2]CPHA [3]select [15:8]clk div
     0x4 DATA
     0x8 STATUS [0]busy
     0xc DC     [0]DC, [1]RST_N(低有效)

   本程序验证"dbus -> rib -> spi"这条通路以及寄存器语义;
   与真实 SPI 设备的时序不在这里验证(测试台把 spi_miso 接 0)。

   结束时把 a0 写到 0x1000_0000, 即测试台约定的"结果信箱"(1 = 通过)。 */
.section .text.init
.globl _start
_start:
    li      s0, 0x20000000          /* SPI 基址 */

    /* 1) DC 复位值: RST_N=1(释放), DC=0 */
    lw      t1, 0xc(s0)
    li      t2, 0x00000002
    bne     t1, t2, fail

    /* 2) 写 DC=0x3, 读回一致 */
    li      t1, 0x00000003
    sw      t1, 0xc(s0)
    lw      t2, 0xc(s0)
    bne     t2, t1, fail

    /* 3) CTRL: 写 div=5/select=1; bit0 是自清使能位, 读回应为 0 */
    li      t1, 0x00000508
    sw      t1, 0x0(s0)
    lw      t2, 0x0(s0)
    bne     t2, t1, fail

    /* 4) 字节使能: sb 只改 DC 低字节 */
    li      t1, 0x000000FA
    sb      t1, 0xc(s0)
    lw      t2, 0xc(s0)
    bne     t2, t1, fail

    /* 5) STATUS 只读: 写不进, 空闲时为 0 */
    li      t1, 0xFFFFFFFF
    sw      t1, 0x8(s0)
    lw      t2, 0x8(s0)
    bne     t2, zero, fail

    /* 6) 启动一次传输: 写 CTRL 带 enable, 先看到 busy, 再等它自己结束。
          div=32 让传输足够慢(17 个 clk 沿 x 33 周期), 以便轮询观察到 busy。 */
    li      t1, 0x00002009
    sw      t1, 0x0(s0)

    li      s1, 1000
20: lw      t2, 0x8(s0)
    andi    t2, t2, 1
    bnez    t2, busy_seen
    addi    s1, s1, -1
    bnez    s1, 20b
    j       fail                    /* 一直没变忙: 传输没启动 */

busy_seen:
    li      s1, 100000
21: lw      t2, 0x8(s0)
    andi    t2, t2, 1
    beqz    t2, idle_seen
    addi    s1, s1, -1
    bnez    s1, 21b
    j       fail                    /* 忙标志一直不落: 传输没结束 */

idle_seen:
    li      a0, 1
    j       finish
fail:
    li      a0, 0
finish:
    li      t0, 0x10000000
    sw      a0, 0(t0)               /* 结果信箱 */
1:  j       1b
