/* LCD 驱动需要的底层 IO. 屏幕是插在扩展口上的模块, 不属于板子: 由 components/lcd/lcd_io.c
 * 经 GPIO 矩阵和 SPI1 实现 (minimal_soc 用 sw/board/lcd_io.c). 驱动本身不接触寄存器. */
#ifndef LCD_IO_H
#define LCD_IO_H

#include <stdint.h>

/* 屏幕接在哪几个引脚 (矩阵引脚编号, 见 bsp/<板>_pins.h), 由 app 给出 */
typedef struct {
    uint32_t sck, mosi, cs, dc, rst, bl;
} lcd_pins_t;

/* 配置总线并选中屏幕. mode: SPI 模式 0~3; max_hz: 屏幕允许的最高 SCK. 由各屏幕驱动调用 */
void lcd_io_init(const lcd_pins_t *pins, uint32_t mode, uint32_t max_hz);
void lcd_io_dc(int level);  /* 0 = 命令, 1 = 数据 */
void lcd_io_rst(int level); /* 0 = 复位, 1 = 正常工作 */
void lcd_io_write_byte(uint8_t data);
void lcd_io_wait(void); /* 等已写入的字节全部发完 */
void lcd_io_delay_ms(uint32_t ms);

#endif
