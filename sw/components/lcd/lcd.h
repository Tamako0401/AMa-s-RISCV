/* 240x320 SPI LCD 驱动, 支持 ST7789 和 ILI9341. 颜色为 RGB565. */
#ifndef LCD_DRV_H
#define LCD_DRV_H

#include <stdint.h>

#define LCD_W 240
#define LCD_H 320

#define RGB565(r, g, b) ((uint16_t)((((r) & 0xF8) << 8) | (((g) & 0xFC) << 3) | ((b) >> 3)))
#define LCD_BLACK 0x0000
#define LCD_WHITE 0xFFFF
#define LCD_RED   0xF800
#define LCD_GREEN 0x07E0
#define LCD_BLUE  0x001F

void lcd_init_st7789(void);
void lcd_init_ili9341(void);

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
