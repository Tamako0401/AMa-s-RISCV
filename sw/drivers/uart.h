/* UART 外设驱动 (8N1, 轮询) */
#ifndef UART_H
#define UART_H

#include "amarisc.h"

/* baud: 例如 115200; clk_hz: 外设时钟。写成 inline: 参数是常量时编译期就算出分频,
 * 因为 rv32i 没有除法指令, -nostdlib 下运行时除法会链接不到 __udivsi3。 */
static inline void uart_init(UART_TypeDef *uart, uint32_t clk_hz, uint32_t baud)
{
    uart->BAUD = (clk_hz + baud / 2) / baud - 1;    /* 50MHz/115200 -> 433, 四舍五入 */
    uart->CTRL = UART_CTRL_TXEN | UART_CTRL_RXEN;
}
void uart_putc(UART_TypeDef *uart, char c);
void uart_puts(UART_TypeDef *uart, const char *s);
/* 收到字节返回 1 并写入 *c, 没收到返回 0 (不等待) */
int uart_getc(UART_TypeDef *uart, char *c);

#endif
