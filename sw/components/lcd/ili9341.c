#include "lcd.h"

#include "lcd_io.h"

#define ILI9341_MAX_HZ 10000000UL    /* 写时钟周期最短 100ns */


static const uint8_t ili9341_seq[] = {
    0x01, LCD_SEQ_DELAY, 150,                       /* SWRESET 软件复位 */
    0xEF, 3, 0x03, 0x80, 0x02,                      /* 以下 5 条是厂商未公开的调校寄存器 */
    0xCF, 3, 0x00, 0xC1, 0x30,                      /* Power control B */
    0xED, 4, 0x64, 0x03, 0x12, 0x81,                /* Power on sequence control */
    0xE8, 3, 0x85, 0x00, 0x78,                      /* Driver timing control A */
    0xCB, 5, 0x39, 0x2C, 0x00, 0x34, 0x02,          /* Power control A */
    0xF7, 1, 0x20,                                  /* Pump ratio control */
    0xEA, 2, 0x00, 0x00,                            /* Driver timing control B */
    0xC0, 1, 0x23,                                  /* 电源控制 1 */
    0xC1, 1, 0x10,                                  /* 电源控制 2 */
    0xC5, 2, 0x3E, 0x28,                            /* VCOM 控制 1 */
    0xC7, 1, 0x86,                                  /* VCOM 控制 2 */
    0x36, 1, 0x48,                                  /* MADCTL 竖屏, BGR 顺序 */
    0x37, 1, 0x00,                                  /* 垂直滚动起点 */
    0x3A, 1, 0x55,                                  /* COLMOD 16 位 RGB565 */
    0xB1, 2, 0x00, 0x18,                            /* 帧率 */
    0xB6, 3, 0x08, 0x82, 0x27,                      /* 显示功能控制 */
    0xF2, 1, 0x00,                                  /* 关闭 3Gamma */
    0x26, 1, 0x01,                                  /* Gamma 曲线 */
    0xE0, 15, 0x0F, 0x31, 0x2B, 0x0C, 0x0E, 0x08,   /* 正 Gamma 校正 */
              0x4E, 0xF1, 0x37, 0x07, 0x10, 0x03,
              0x0E, 0x09, 0x00,
    0xE1, 15, 0x00, 0x0E, 0x14, 0x03, 0x11, 0x07,   /* 负 Gamma 校正 */
              0x31, 0xC1, 0x48, 0x08, 0x0F, 0x0C,
              0x31, 0x36, 0x0F,
    0x11, LCD_SEQ_DELAY, 120,                       /* SLPOUT 退出睡眠 */
    0x29, LCD_SEQ_DELAY, 100,                       /* DISPON 打开显示 */
};

void lcd_init_ili9341(const lcd_pins_t *pins)
{
    lcd_io_init(pins, 0, ILI9341_MAX_HZ);
    lcd_w = 240;
    lcd_h = 320;
    lcd_reset();
    lcd_run_seq(ili9341_seq, sizeof(ili9341_seq));
}
