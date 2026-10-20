/* 屏幕 shield: 本板默认插的屏幕模块是什么型号、插在哪个口. 换口或换屏只改这里.
 * 屏幕不是板子的一部分 (见 components/lcd/lcd_io.h), 但每块板有一个约定的插法, 写在这一处.
 * app 用自己的接法时不调 shield_lcd_init, 直接调 lcd_init_<型号>(&(lcd_pins_t){...}).
 * 只有头文件: 不用改 ama / build-board.py 的源文件列表. */
#ifndef SHIELD_LCD_H
#define SHIELD_LCD_H

#include "bsp.h"
#include "lcd.h"

#ifdef BOARD_EGO1
/* ST7735S 128x160, 插 J5 */
#define SHIELD_LCD_PINS { .sck = PIN_J5_1, .mosi = PIN_J5_2, .rst = PIN_J5_3, \
                          .dc = PIN_J5_4, .bl = PIN_J5_5, .cs = PIN_J5_6 }
#define SHIELD_LCD_INIT lcd_init_st7735
#else
/* ST7789 240x320, 插 J8 的 23~28 脚 */
#define SHIELD_LCD_PINS { .sck = PIN_J8_27, .mosi = PIN_J8_28, .cs = PIN_J8_23, \
                          .dc = PIN_J8_26, .rst = PIN_J8_25, .bl = PIN_J8_24 }
#define SHIELD_LCD_INIT lcd_init_st7789
#endif

/* 按本板默认的型号和接法初始化屏幕; 之后用 lcd_width()/lcd_height() 读宽高 */
static inline void shield_lcd_init(void)
{
    static const lcd_pins_t pins = SHIELD_LCD_PINS;
    SHIELD_LCD_INIT(&pins);
}

#endif
