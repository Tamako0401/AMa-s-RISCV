/* RIB integration: persistent CR1, write-to-send DR, GPIO BSRR control.
 * SPI 0x20000000: CR1/CR2/SR/DR at 0/4/8/C.
 * GPIO 0x40000000: CTRL/DATA/BSRR at 0/4/8; pins 0=CS, 1=DC, 2=RST_N.
 * The testbench checks the external control pins and exactly 32 SCK edges.
 * Independent four-mode/full-duplex timing tests are in reusable/spi_tb.sv.
 */
.section .text.init
.globl _start
_start:
    li s0, 0x20000000
    li s2, 0x40000000
    lw t1, 0(s0)
    li t2, 4
    bne t1, t2, fail
    lw t1, 8(s0)
    li t2, 2
    bne t1, t2, fail
    li t1, -1
    sw t1, 4(s0)                 /* reserved CR2 remains zero */
    lw t1, 4(s0)
    bnez t1, fail
    sw zero, 8(s0)               /* SR is hardware-owned */
    lw t1, 8(s0)
    bne t1, t2, fail

    li t1, 5
    sw t1, 8(s2)                 /* preload CS=1, RST_N=1 before output mode */
    li t1, 0x15
    sw t1, 0(s2)                 /* pins 0/1/2 output */
    lw t1, 4(s2)
    li t2, 5
    bne t1, t2, fail
    li t1, 0x00010002
    sw t1, 8(s2)                 /* one write: CS=0, DC=1 */
    lw t1, 4(s2)
    li t2, 6
    bne t1, t2, fail
    li t1, 4
    sb t1, 10(s2)                /* upper BSRR byte clears RST_N */
    lw t1, 4(s2)
    li t2, 2
    bne t1, t2, fail
    sh t1, 8(s2)                 /* setting DC must preserve RST_N=0 */
    li t1, 4
    sh t1, 8(s2)                 /* lower BSRR halfword releases RST_N */
    lw t1, 4(s2)
    li t2, 6
    bne t1, t2, fail

    li s3, 0x7c                  /* MSTR=1, SPE=1, BR=7 (/256), mode 0 */
    sw s3, 0(s0)
    li t1, 0xa5
    sb t1, 12(s0)                /* DR write alone starts transfer */
    li s1, 1000
1:  lw t2, 8(s0)
    andi t2, t2, 0x80
    bnez t2, busy_seen
    addi s1, s1, -1
    bnez s1, 1b
    j fail
busy_seen:
    li t1, 0x3c
    sb t1, 12(s0)                /* queue second byte without touching CR1 */
    li s1, 100000
2:  lw t2, 8(s0)
    andi t2, t2, 0x80
    beqz t2, complete
    addi s1, s1, -1
    bnez s1, 2b
    j fail
complete:
    lw t1, 8(s0)
    li t2, 0x43                  /* oldest RX retained, OVR, TXE, no BSY */
    bne t1, t2, fail
    lw t1, 12(s0)                /* MISO fixed 0; reading DR consumes RX */
    bnez t1, fail
    lw t1, 8(s0)                 /* reads pre-clear OVR and clears it */
    li t2, 0x42
    bne t1, t2, fail
    lw t1, 8(s0)
    li t2, 2
    bne t1, t2, fail
    li t1, 1
    sw t1, 8(s2)                 /* release CS only after BSY=0 */
    lw t1, 4(s2)
    li t2, 7
    bne t1, t2, fail
    lw t1, 0(s0)
    bne t1, s3, fail              /* SPE/configuration did not self-clear */
    sb t1, 13(s0)                /* upper DR byte must not start SPI */
    lw t1, 8(s0)
    li t2, 2
    bne t1, t2, fail
    li a0, 1
    j finish
fail:
    li a0, 0
finish:
    li t0, 0x10000000
    sw a0, 0(t0)
3:  j 3b
