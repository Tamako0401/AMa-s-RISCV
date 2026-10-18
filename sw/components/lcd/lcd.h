/* SPI LCD 驱动, 支持 ST7789 / ILI9341 (240x320) 和 ST7735S (128x160). 颜色为 RGB565. */
#ifndef LCD_DRV_H
#define LCD_DRV_H

#include <stdint.h>
#include "lcd_io.h"

extern uint16_t lcd_w, lcd_h;
static inline uint16_t lcd_width(void) { return lcd_w; }
static inline uint16_t lcd_height(void) { return lcd_h; }

#define RGB565(r, g, b) ((uint16_t)((((r) & 0xF8) << 8) | (((g) & 0xFC) << 3) | ((b) >> 3)))
#define LCD_BLACK 0x0000
#define LCD_WHITE 0xFFFF
#define LCD_RED   0xF800
#define LCD_GREEN 0x07E0
#define LCD_BLUE  0x001F

/* 初始化屏幕; 宽高由驱动设好, 之后用 lcd_width()/lcd_height() 读 */
void lcd_init_st7789(const lcd_pins_t *pins);
void lcd_init_ili9341(const lcd_pins_t *pins);
void lcd_init_st7735(const lcd_pins_t *pins);

void lcd_set_window(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1);
void lcd_draw_pixel(uint16_t x, uint16_t y, uint16_t color);
void lcd_fill_rect(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint16_t color);
void lcd_fill(uint16_t color);
void lcd_draw_line(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint16_t color);

/* 以下供各屏幕的初始化序列使用 */
void lcd_write_cmd(uint8_t cmd);
void lcd_write_data(const uint8_t *data, uint32_t len);
void lcd_reset(void);
/* 初始化序列格式: 命令, 参数个数[|LCD_SEQ_DELAY], 参数..., [延时 ms] */
#define LCD_SEQ_DELAY 0x80
void lcd_run_seq(const uint8_t *seq, uint32_t len);

#endif
