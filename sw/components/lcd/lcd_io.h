/* LCD 驱动需要的底层 IO, 由 BSP 实现. 驱动本身不接触寄存器. */
#ifndef LCD_IO_H
#define LCD_IO_H

#include <stdint.h>

/* 配置总线并选中屏幕. mode: SPI 模式 0~3; max_hz: 屏幕允许的最高 SCK */
void lcd_io_init(uint32_t mode, uint32_t max_hz);
void lcd_io_dc(int level);              /* 0 = 命令, 1 = 数据 */
void lcd_io_rst(int level);             /* 0 = 复位, 1 = 正常工作 */
void lcd_io_write_byte(uint8_t data);
void lcd_io_wait(void);                 /* 等已写入的字节全部发完 */
void lcd_io_delay_ms(uint32_t ms);

#endif
