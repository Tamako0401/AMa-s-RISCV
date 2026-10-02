/* Peripheral bus integration: UART at port 1 and LEDs on GPIO 8..15.
 * UART 0x40001000: CTRL/STATUS/BAUD/TXDATA/RXDATA at 0/4/8/C/10.
 * GPIO 0x40000000: CTRL/DATA at 0/4.
 * The testbench decodes 'A' and 'Z' from the uart_tx pin, then drives 0x3C on
 * uart_rx, and checks led == 0xA5 at the end. Stores: 7.
 */
.section .text.init
.globl _start
_start:
    li s0, 0x40001000
    li s2, 0x40000000

    /* 1) 读通路: 写 BAUD=16(每位 17 拍, 仿真快), 读回必须一致 */
    li t1, 16
    sw t1, 8(s0)
    lw t2, 8(s0)
    bne t2, t1, fail

    /* 2) 打开 TX/RX, 依次发 'A' 'Z', 每次等 TX 空闲 */
    li t1, 3
    sw t1, 0(s0)
    li a1, 0x41
    jal ra, send
    li a1, 0x5a
    jal ra, send

    /* 3) 等测试台从 uart_rx 发来的 0x3C, 读出后清 RX 完成标志 */
    li s1, 100000
1:  lw t2, 4(s0)
    andi t2, t2, 2
    bnez t2, 2f
    addi s1, s1, -1
    bnez s1, 1b
    j fail
2:  lw t2, 16(s0)
    li t1, 0x3c
    bne t2, t1, fail
    sw zero, 4(s0)
    lw t2, 4(s0)
    andi t2, t2, 2
    bnez t2, fail

    /* 4) LED: GPIO 8..15 设为输出, 写 0xA5 */
    li t1, 0x55550000
    sw t1, 0(s2)
    li t1, 0x0000a500
    sw t1, 4(s2)

    li a0, 1
    j finish

/* 发送 a1 的低字节并等待发送完成 */
send:
    sw a1, 12(s0)
    li s1, 100000
3:  lw t2, 4(s0)
    andi t2, t2, 1
    beqz t2, 4f
    addi s1, s1, -1
    bnez s1, 3b
    j fail
4:  ret

fail:
    li a0, 0
finish:
    li t0, 0x10000000
    sw a0, 0(t0)
5:  j 5b
