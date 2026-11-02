/* uart2_check: 第二个串口 (0x4000_7000) 经 GPIO 矩阵接到一个扩展口引脚上回环收发。
 *
 * 测试台 (soc_tb +loopback) 把每个正在输出的 inout 脚的电平送回它自己的输入, 和实机上 IO 缓冲读回管脚一样。
 * UART2_TX 和 UART2_RX 都接 J8_3, 发出去的字节应当原样收回来:
 *   1. 上电时 UART2 的两个信号都没接: FUNC_IN_SEL[2] = 0xFF, 发一个字节收不到 (RX 是空闲电平 1);
 *   2. 改 UART2 的分频不影响控制台串口 (两个口地址没串);
 *   3. 接上以后发 0x55 0xA3 0x00 0x7F 0xFF, 依次收回; 控制台串口什么也没收到;
 *   4. 断开 RX (0xFF) 再发, 收不到。
 * 通过: main 返回 1 (start.S 写进结束信箱)。失败返回 0x10 + 第几步。 */
#include <stdint.h>

#include "bsp.h"
#include "io.h"
#include "uart.h"

#define PIN PIN_J8_3 /* 测试按 mes50hp 的引脚表编译 */

static const uint8_t bytes[] = {0x55, 0xA3, 0x00, 0x7F, 0xFF};

/* 等 UART2 收到一个字节, 最多等 limit 次查询; 收到返回 1 */
static int wait_byte(uint32_t limit, char *c)
{
    while (limit--)
        if (uart_getc(UART2, c))
            return 1;
    return 0;
}

int main(void)
{
    char c;
    if (IO_MATRIX->FUNC_IN_SEL[SIG_UART2_RX] != IO_NONE || IO_MATRIX->FUNC_OUT_SEL[PIN] != SIG_GPIO)
        return 0x11;
    UART2->BAUD = 16; /* 每位 17 拍, 仿真快 */
    UART2->CTRL = UART_CTRL_TXEN | UART_CTRL_RXEN;
    if (UART2->BAUD != 16 || UART1->BAUD == 16)
        return 0x12;
    uart_putc(UART2, 0x5A);
    if (wait_byte(2000, &c))
        return 0x11;

    io_connect_out(PIN, SIG_UART2_TX);
    io_connect_in(SIG_UART2_RX, PIN);
    for (uint32_t i = 0; i < sizeof bytes; i++) {
        uart_putc(UART2, (char)bytes[i]);
        if (!wait_byte(2000, &c) || (uint8_t)c != bytes[i])
            return 0x13;
    }
    if (UART1->STATUS & UART_STATUS_RXDONE)
        return 0x13;

    io_connect_in(SIG_UART2_RX, IO_NONE);
    uart_putc(UART2, 0x3C);
    if (wait_byte(2000, &c))
        return 0x14;
    return 1;
}
