#include "uart.h"

void uart_putc(UART_TypeDef *uart, char c)
{
    while (uart->STATUS & UART_STATUS_TXBUSY)
        ;
    uart->TXDATA = (uint8_t)c;
}

void uart_puts(UART_TypeDef *uart, const char *s)
{
    while (*s)
        uart_putc(uart, *s++);
}

int uart_getc(UART_TypeDef *uart, char *c)
{
    if (!(uart->STATUS & UART_STATUS_RXDONE))
        return 0;
    *c = (char)uart->RXDATA;
    uart->STATUS = 0; /* 清 RX 完成标志 */
    return 1;
}
