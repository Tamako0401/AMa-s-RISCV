#include "lcd.h"
#include "lcd_io.h"

uint16_t lcd_w, lcd_h;

/* 改 DC 前要等上一个字节真正发完 */
void lcd_write_cmd(uint8_t cmd)
{
    lcd_io_wait();
    lcd_io_dc(0);
    lcd_io_write_byte(cmd);
}

void lcd_write_data(const uint8_t *data, uint32_t len)
{
    lcd_io_wait();
    lcd_io_dc(1);
    while (len--)
        lcd_io_write_byte(*data++);
}

/* 硬件复位: 拉低 RST 至少 10us, 释放后等待屏幕内部复位完成 */
void lcd_reset(void)
{
    lcd_io_rst(0);
    lcd_io_delay_ms(10);
    lcd_io_rst(1);
    lcd_io_delay_ms(120);
}

void lcd_run_seq(const uint8_t *seq, uint32_t len)
{
    const uint8_t *end = seq + len;
    while (seq < end) {
        uint8_t cmd = *seq++;
        uint8_t n = *seq++;
        lcd_write_cmd(cmd);
        if (n & ~LCD_SEQ_DELAY)
            lcd_write_data(seq, n & ~LCD_SEQ_DELAY);
        seq += n & ~LCD_SEQ_DELAY;
        if (n & LCD_SEQ_DELAY) {
            lcd_io_wait();
            lcd_io_delay_ms(*seq++);
        }
    }
    lcd_io_wait();
}

/* 设置写入区域(含两端), 之后写入的像素依次填满该区域 */
void lcd_set_window(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1)
{
    uint8_t col[4] = {x0 >> 8, x0 & 0xFF, x1 >> 8, x1 & 0xFF};
    uint8_t row[4] = {y0 >> 8, y0 & 0xFF, y1 >> 8, y1 & 0xFF};

    lcd_write_cmd(0x2A); /* CASET 列地址 */
    lcd_write_data(col, 4);
    lcd_write_cmd(0x2B); /* RASET 行地址 */
    lcd_write_data(row, 4);
    lcd_write_cmd(0x2C); /* RAMWR 开始写显存 */
}

void lcd_fill_rect(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint16_t color)
{
    if (x >= lcd_width() || y >= lcd_height() || w == 0 || h == 0)
        return;
    if (x + w > lcd_width())
        w = lcd_width() - x;
    if (y + h > lcd_height())
        h = lcd_height() - y;

    lcd_set_window(x, y, x + w - 1, y + h - 1);
    lcd_io_wait();
    lcd_io_dc(1);
    /* 双重循环而不是 w * h: rv32i 没有乘法指令 */
    for (uint16_t j = 0; j < h; j++) {
        for (uint16_t i = 0; i < w; i++) {
            lcd_io_write_byte(color >> 8);
            lcd_io_write_byte(color & 0xFF);
        }
    }
}

void lcd_draw_pixel(uint16_t x, uint16_t y, uint16_t color)
{
    lcd_fill_rect(x, y, 1, 1, color);
}

/* Bresenham 画线; 水平/竖直线直接填矩形 */
void lcd_draw_line(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint16_t color)
{
    if (y0 == y1) {
        lcd_fill_rect(x0 < x1 ? x0 : x1, y0, (x0 < x1 ? x1 - x0 : x0 - x1) + 1, 1, color);
        return;
    }
    if (x0 == x1) {
        lcd_fill_rect(x0, y0 < y1 ? y0 : y1, 1, (y0 < y1 ? y1 - y0 : y0 - y1) + 1, color);
        return;
    }

    int32_t dx = x1 > x0 ? x1 - x0 : x0 - x1;
    int32_t dy = y1 > y0 ? y0 - y1 : y1 - y0; /* 取负 */
    int32_t sx = x0 < x1 ? 1 : -1;
    int32_t sy = y0 < y1 ? 1 : -1;
    int32_t err = dx + dy;
    int32_t x = x0, y = y0;

    for (;;) {
        lcd_draw_pixel(x, y, color);
        if (x == x1 && y == y1)
            break;
        int32_t e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y += sy;
        }
    }
}

void lcd_fill(uint16_t color)
{
    lcd_fill_rect(0, 0, lcd_width(), lcd_height(), color);
}
