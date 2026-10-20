/* hello: 串口打招呼, 屏幕中间画一个蓝色块, LED 每 0.5 秒亮灭一次, 串口收到什么回什么 */
#include "bsp.h"
#include "io.h"
#include "uart.h"
#include "lcd.h"
#include "shield_lcd.h"
#include "app_board.h" /* 本板接线: boards/<板>/ */

int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    uart_puts(CONSOLE_UART, "hello\r\n");

    shield_lcd_init();
    lcd_fill(LCD_BLACK);
    lcd_fill_rect(lcd_width() >> 2, lcd_height() >> 2, lcd_width() >> 1, lcd_height() >> 1, LCD_BLUE);

    io_dir(LED, IO_OUTPUT);
    uint32_t step = bsp_ms_to_cycles(500), last = bsp_cycles();
    int on = 0;
    for (;;) {
        if (bsp_cycles() - last >= step) {
            last += step;
            on = !on;
            io_write(LED, on);
        }
        char c;
        if (uart_getc(CONSOLE_UART, &c))
            uart_putc(CONSOLE_UART, c);
    }
}
