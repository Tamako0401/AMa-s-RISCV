/* 为 components/lcd 实现 lcd_io.h: 屏幕引脚经 GPIO 矩阵, 数据走 SPI1 */
#include "bsp.h"
#include "io.h"
#include "spi.h"
#include "lcd_io.h"

static uint32_t cs_pin, dc_pin, rst_pin;

void lcd_io_init(const lcd_pins_t *pins, uint32_t mode, uint32_t max_hz)
{
    uint32_t sck = pins->sck, mosi = pins->mosi, cs = pins->cs, dc = pins->dc, rst = pins->rst, bl = pins->bl;
    cs_pin = cs;
    dc_pin = dc;
    rst_pin = rst;
    uint32_t br = 0;
    while (br < 7 && (SYSCLK_HZ >> (br + 1)) > max_hz)
        br++;
    /* 先给安全电平再开输出, SPI 配好空闲电平后才接到屏幕。 */
    io_write(cs, 1);
    io_write(dc, 0);
    io_write(rst, 1);
    io_write(bl, 1);
    io_connect_out(cs, SIG_GPIO);
    io_connect_out(dc, SIG_GPIO);
    io_connect_out(rst, SIG_GPIO);
    io_connect_out(bl, SIG_GPIO);
    io_dir(cs, IO_OUTPUT);
    io_dir(dc, IO_OUTPUT);
    io_dir(rst, IO_OUTPUT);
    io_dir(bl, IO_OUTPUT);
    spi_init(SPI1, mode, br);
    io_connect_out(sck, SIG_SPI_SCK);
    io_connect_out(mosi, SIG_SPI_MOSI);
    io_write(cs, 0);
}

/* 字节边界重新选中屏幕, 让偶发 SCK 毛刺只影响这一段。 */
void lcd_io_dc(int level)
{
    io_write(cs_pin, 1);
    io_write(cs_pin, 0);
    io_write(dc_pin, level);
}

void lcd_io_rst(int level) { io_write(rst_pin, level); }
void lcd_io_write_byte(uint8_t data) { spi_write_byte(SPI1, data); }
void lcd_io_wait(void) { spi_wait_idle(SPI1); }
void lcd_io_delay_ms(uint32_t ms) { delay_ms(ms); }
