#include "lcd.h"

#include "lcd_io.h"

#define ST7789_MAX_HZ 60000000UL     /* 写时钟周期最短 16ns */


/* 寄存器取值对齐目标模块 GMT024-8p10p-SPI 的厂商例程
 * (资料包 3-SPI显示屏硬件手册/GMT024-8p10p-SPI-ST7789.c, ST7789V2):
 * VCOM/porch/gamma 逐值照抄; 厂商用硬件复位, 不用 SWRESET;
 * 厂商发 0x20 INVOFF, 即本模块不需要颜色反转;
 * COLMOD 写 0x55, 与厂商的 0x05 同为 16 位 RGB565 (仿真模型校验 0x55)。 */
static const uint8_t st7789_seq[] = {
    0x11, LCD_SEQ_DELAY, 120,           /* SLPOUT 退出睡眠 */
    0x3A, 1, 0x55,                      /* COLMOD 16 位 RGB565 */
    0xC5, 1, 0x1A,                      /* VCOM */
    0x36, 1, 0x00,                      /* MADCTL 竖屏, 从左上开始 */
    0xB2, 5, 0x05, 0x05, 0x00, 0x33, 0x33, /* Porch */
    0xB7, 1, 0x05,                      /* Gate 控制 */
    0xBB, 1, 0x3F,                      /* VCOM */
    0xC0, 1, 0x2C,                      /* 电源控制 */
    0xC2, 1, 0x01,                      /* VDV/VRH 使能 */
    0xC3, 1, 0x0F,                      /* VRH */
    0xC4, 1, 0x20,                      /* VDV */
    0xC6, 1, 0x01,                      /* 帧率 111 Hz */
    0xD0, 2, 0xA4, 0xA1,                /* 电源控制 1 */
    0xE8, 1, 0x03,                      /* 电源控制 */
    0xE9, 3, 0x09, 0x09, 0x08,          /* 均衡时间 */
    0xE0, 14, 0xD0, 0x05, 0x09, 0x09, 0x08, 0x14, 0x28,
              0x33, 0x3F, 0x07, 0x13, 0x14, 0x28, 0x30, /* 正 gamma */
    0xE1, 14, 0xD0, 0x05, 0x09, 0x09, 0x08, 0x03, 0x24,
              0x32, 0x32, 0x3B, 0x14, 0x13, 0x28, 0x2F, /* 负 gamma */
    0x20, 0,                            /* INVOFF: 厂商明确本模块不反转 */
    0x29, LCD_SEQ_DELAY, 100,           /* DISPON 打开显示 */
};

void lcd_init_st7789(const lcd_pins_t *pins)
{
    lcd_io_init(pins, 3, ST7789_MAX_HZ); /* 模式 3, 与厂商 bit-bang 一致: 空闲高, 上升沿采样 */
    lcd_w = 240;
    lcd_h = 320;
    lcd_reset();
    lcd_run_seq(st7789_seq, sizeof(st7789_seq));
}
