#include "board_hdmi.h"
#include "bsp.h"
#include "uart.h"

volatile uint64_t tohost __attribute__((section(".tohost")));

int main(void)
{
    /* 上板诊断: 最先点亮 LED8, 不经过 UART 和 I2C。亮 = CPU 确实执行到 main;
     * 之后串口打印 boot, 再初始化 HDMI, 这样能把"CPU 没跑"和"卡在初始化"分开。 */
    io_dir(PIN_LED8, IO_OUTPUT);
    io_write(PIN_LED8, 1);

    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    uart_puts(CONSOLE_UART, "boot\r\n");
    int status = board_hdmi_init();
    if (status & 1)
        uart_puts(CONSOLE_UART, "HDMI out: no answer\r\n");
    else
        uart_puts(CONSOLE_UART, "OV7670 VGA monitor ready\r\n");
    tohost = 1;
    uint32_t half_period_ms = status & 1 ? 500 : 167;
    int led_level = 0;
    for (;;) {
        led_level = !led_level;
        io_write(PIN_LED8, led_level);
        delay_ms(half_period_ms);
    }
}
