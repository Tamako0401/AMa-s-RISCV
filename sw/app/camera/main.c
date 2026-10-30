#include "board_hdmi.h"
#include "bsp.h"
#include "uart.h"

volatile uint64_t tohost __attribute__((section(".tohost")));

int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    int status = board_hdmi_init();
    if (status & 1)
        uart_puts(CONSOLE_UART, "HDMI out: no answer\r\n");
    else
        uart_puts(CONSOLE_UART, "OV7670 VGA monitor ready\r\n");
    tohost = 1;
    for (;;)
        ;
}
