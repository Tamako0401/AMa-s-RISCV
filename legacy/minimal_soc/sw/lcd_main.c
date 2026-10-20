/* MES50HP 板级 SPI 屏幕演示: 与 sw/app/lcd_demo 相同的画面
 * (清屏、白边框、绿对角线、红/绿/蓝色块), 跑在 minimal_soc 上。
 * 地址: 统一 RAM 0x80000000, UART 0x30000000, GPIO 0x40000000, SPI 0x40002000。
 * GPIO 0/1/2 = LCD CS_N/DC/RST_N, GPIO 8~15 = LED。构建与仿真见 scripts/build-board.py --lcd。 */
#include "lcd.h"
#include "lcd_io.h"
#include "bsp.h"
#include "gpio.h"

typedef unsigned int u32;
#define REG(a) (*(volatile u32 *)(a))
#define UART 0x30000000u

/* 仿真测试台把对这里的写当作程序结束; 位于栈保护区之下, 见 sw/board/link.ld */
#define TOHOST (*(volatile u32 *)0x8000F000u)

static void putc_uart(char c) {
    while (REG(UART+4) & 1u) {}
    REG(UART+12) = (unsigned char)c;
}
static void puts_uart(const char *s) { while (*s) putc_uart(*s++); }

int main(void)
{
    REG(UART+8) = 433; // 50 MHz / (433+1), approx. 115207 baud
    REG(UART) = 3;     // TX + RX
    gpio_set_mode(GPIO, 0xFF00u, GPIO_MODE_OUTPUT); // LED on GPIO 8~15
    gpio_reset(GPIO, 0xFF00u);

    lcd_init_st7789(&(lcd_pins_t){ 0 });     /* minimal_soc 的引脚是固定的, 见 sw/board/lcd_io.c */
    lcd_fill(LCD_BLACK);

    /* 边框 */
    lcd_draw_line(0, 0, lcd_width() - 1, 0, LCD_WHITE);
    lcd_draw_line(0, lcd_height() - 1, lcd_width() - 1, lcd_height() - 1, LCD_WHITE);
    lcd_draw_line(0, 0, 0, lcd_height() - 1, LCD_WHITE);
    lcd_draw_line(lcd_width() - 1, 0, lcd_width() - 1, lcd_height() - 1, LCD_WHITE);

    /* 对角线 */
    lcd_draw_line(0, 0, lcd_width() - 1, lcd_height() - 1, LCD_GREEN);

    /* 色块 */
    lcd_fill_rect(20, 20, 40, 40, LCD_RED);
    lcd_fill_rect(100, 20, 40, 40, LCD_GREEN);
    lcd_fill_rect(180, 20, 40, 40, LCD_BLUE);

    puts_uart("AMA LCD PASS\r\n");
    TOHOST = 1;

    /* 画完后 LED 呼吸移位, 便于实机确认 CPU 仍在运行 */
    u32 previous; __asm__ volatile ("rdcycle %0" : "=r"(previous));
    u32 pattern = 1;
    for (;;) {
        u32 now; __asm__ volatile ("rdcycle %0" : "=r"(now));
        if (now - previous >= 25000000u) {
            previous = now;
            pattern = pattern == 128 ? 1 : pattern << 1;
            u32 led_on = pattern << 8;
            u32 led_off = 0xFF00u & ~led_on;
            GPIO->BSRR = (led_off << 16) | led_on;
        }
    }
}
