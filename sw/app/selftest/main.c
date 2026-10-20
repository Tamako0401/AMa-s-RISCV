/* 自检: 烧进位流的默认程序, 上电一次看全 CPU、屏幕、按键、LED、串口. 说明见 README.md */
#include "bsp.h"
#include "io.h"
#include "uart.h"
#include "lcd.h"
#include "shield_lcd.h"
#include "key.h"
#include "app_board.h" /* 本板的 LED 表、按键表、按键方块位置: boards/<板>/ */

#include "cpu_test.h"

#define LED_STEP_MS 500
#define KEY_SIZE 12
#define GRAY RGB565(48, 48, 48)

/* 仿真时测试台把对这里的写当作画完 (sw/link.ld 把 .tohost 放在 RAM 开头); 上板没人看, 写了无害 */
volatile uint64_t tohost __attribute__((section(".tohost")));

static void show_leds(uint32_t pattern)
{
    for (uint32_t i = 0; i < LED_N; i++)
        io_write(leds[i], (pattern >> i) & 1);
}

/* 测试图: 白边框、绿对角线、红绿蓝三个色块 (tests/soc/lcd_tb.sv 逐点核对) */
static void draw_test_pattern(void)
{
    uint16_t w = lcd_width(), h = lcd_height();
    lcd_fill(LCD_BLACK);
    lcd_draw_line(0, 0, w - 1, 0, LCD_WHITE);
    lcd_draw_line(0, h - 1, w - 1, h - 1, LCD_WHITE);
    lcd_draw_line(0, 0, 0, h - 1, LCD_WHITE);
    lcd_draw_line(w - 1, 0, w - 1, h - 1, LCD_WHITE);
    lcd_draw_line(0, 0, w - 1, h - 1, LCD_GREEN);
    /* 色块边长 w/4, 间隔 w/16 (rv32i 没有除法指令, 只用移位): 240 宽时 x = 15 / 90 / 165 */
    uint16_t gap = w >> 4, size = w >> 2;
    lcd_fill_rect(gap, gap, size, size, LCD_RED);
    lcd_fill_rect(2 * gap + size, gap, size, size, LCD_GREEN);
    lcd_fill_rect(3 * gap + 2 * size, gap, size, size, LCD_BLUE);
}

static void draw_key(uint32_t i, int pressed)
{
    lcd_fill_rect(key_pos[i].x, key_pos[i].y, KEY_SIZE, KEY_SIZE, pressed ? LCD_WHITE : GRAY);
}

int main(void)
{
    for (uint32_t i = 0; i < LED_N; i++)
        io_dir(leds[i], IO_OUTPUT);
    show_leds(1);
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);

    /* 1. CPU 和内存 */
    uint32_t error = cpu_test();
    if (error) {
        show_leds(0x80 | error); /* 最高位亮 + 低位是 FAIL 码 */
        uart_puts(CONSOLE_UART, "AMA CPU FAIL ");
        uart_putc(CONSOLE_UART, '0' + error);
        uart_puts(CONSOLE_UART, "\r\n");
        for (;;)
            ;
    }
    uart_puts(CONSOLE_UART, "AMA CPU PASS\r\n");

    /* 2. 屏幕 */
    shield_lcd_init();
    draw_test_pattern();
    for (uint32_t i = 0; i < KEY_N; i++)
        draw_key(i, 0);
    tohost = 1;

    /* 3. LED 流水 (CPU 在跑), 串口回显, 按键 -> 方块变白 + 串口打印 */
    uint32_t step = bsp_ms_to_cycles(LED_STEP_MS);
    uint32_t last = bsp_cycles(), pattern = 1;
    for (;;) {
        if (bsp_cycles() - last >= step) {
            last += step;
            pattern = pattern == 1UL << (LED_N - 1) ? 1 : pattern << 1;
            show_leds(pattern);
        }
        char c;
        if (uart_getc(CONSOLE_UART, &c)) /* 收到什么就回什么 */
            uart_putc(CONSOLE_UART, c);
        key_ticks(keys, KEY_N);
        for (uint32_t i = 0; i < KEY_N; i++) {
            if (key_rose(&keys[i]) || key_fell(&keys[i])) {
                draw_key(i, key_status(&keys[i]));
                uart_puts(CONSOLE_UART, key_status(&keys[i]) ? "KEY DOWN " : "KEY UP ");
                uart_putc(CONSOLE_UART, '0' + i);
                uart_puts(CONSOLE_UART, "\r\n");
            }
        }
    }
}
