/* 屏幕演示: 清屏, 画边框和对角线, 再画三个色块. 编译与仿真见 justfile 的 app / app-sim. */
#include "lcd.h"
#include "bsp.h"

/* 仿真时测试台把对这里的写当作程序结束 (sw/link.ld 把 .tohost 放在 RAM 开头) */
volatile uint64_t tohost __attribute__((section(".tohost")));
// spike也用不了fromhost不管了.

int main(void)
{
#ifdef BOARD_EGO1
    lcd_init_st7735(&(lcd_pins_t){ .sck = PIN_J5_1, .mosi = PIN_J5_2, .rst = PIN_J5_3,
                                   .dc = PIN_J5_4, .bl = PIN_J5_5, .cs = PIN_J5_6 });
#else
    lcd_init_st7789(&(lcd_pins_t){ .sck = PIN_J8_27, .mosi = PIN_J8_28, .cs = PIN_J8_23,
                                   .dc = PIN_J8_26, .rst = PIN_J8_25, .bl = PIN_J8_24 });
#endif
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

    tohost = 1;
    for (;;)
        ;
}
