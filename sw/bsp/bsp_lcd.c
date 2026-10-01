/* 为 components/lcd 实现 lcd_io.h */
#include "bsp.h"
#include "spi.h"
#include "gpio.h"
#include "lcd_io.h"

/* 先把输出值设成安全电平(不选中, 不复位), 再改为输出; 配好 SPI 模式后才拉低 CS,
 * 否则 CPOL=1 时 SCK 的跳变会被屏幕当成一个比特 */
void lcd_io_init(uint32_t mode, uint32_t max_hz)
{
    uint32_t br = 0;
    while (br < 7 && (SYSCLK_HZ >> (br + 1)) > max_hz)
        br++;

    gpio_set(GPIO, LCD_CS_N_PIN | LCD_RST_N_PIN);
    gpio_reset(GPIO, LCD_DC_PIN);
    gpio_set_mode(GPIO, LCD_CS_N_PIN | LCD_DC_PIN | LCD_RST_N_PIN, GPIO_MODE_OUTPUT);
    spi_init(LCD_SPI, mode, br);
    gpio_reset(GPIO, LCD_CS_N_PIN);     /* 只有一个从设备, 一直选中 */
}

void lcd_io_dc(int level)
{
    if (level)
        gpio_set(GPIO, LCD_DC_PIN);
    else
        gpio_reset(GPIO, LCD_DC_PIN);
}

void lcd_io_rst(int level)
{
    if (level)
        gpio_set(GPIO, LCD_RST_N_PIN);
    else
        gpio_reset(GPIO, LCD_RST_N_PIN);
}

void lcd_io_write_byte(uint8_t data)
{
    spi_write_byte(LCD_SPI, data);
}

void lcd_io_wait(void)
{
    spi_wait_idle(LCD_SPI);
}

void lcd_io_delay_ms(uint32_t ms)
{
    delay_ms(ms);
}
