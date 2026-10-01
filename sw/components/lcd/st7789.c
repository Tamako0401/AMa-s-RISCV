#include "lcd.h"

#include "lcd_io.h"

#define ST7789_MAX_HZ 60000000UL     /* 写时钟周期最短 16ns */

static const uint8_t st7789_seq[] = {
    0x01, LCD_SEQ_DELAY, 150,           /* SWRESET 软件复位 */
    0x11, LCD_SEQ_DELAY, 120,           /* SLPOUT 退出睡眠 */
    0x3A, 1 | LCD_SEQ_DELAY, 0x55, 10,  /* COLMOD 16 位 RGB565 */
    0x36, 1, 0x00,                      /* MADCTL 竖屏, 从左上开始 */
    0x21, 0,                            /* INVON 颜色反转, 多数 ST7789 模块需要, 否则颜色是反的 */
    0x13, LCD_SEQ_DELAY, 10,            /* NORON 正常显示模式 */
    0x29, LCD_SEQ_DELAY, 100,           /* DISPON 打开显示 */
};

void lcd_init_st7789(void)
{
    lcd_io_init(3, ST7789_MAX_HZ);     /* 模式 3; 部分模块用模式 0 */
    lcd_reset();
    lcd_run_seq(st7789_seq, sizeof(st7789_seq));
}
