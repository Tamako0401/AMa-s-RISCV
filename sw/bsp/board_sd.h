/* SD 卡接在哪, 换脚只改这里 (见 docs/sd.md):
 *   默认: 100HP 板载 MicroSD 卡槽 J10 (SD_SCK/MOSI/MISO/CS, L3 bank 3.3 V)。
 *   -DSD_EXTERNAL: 外接 3.3 V SPI SD 模块, 接 EXT29~32 (L6 bank, 先核实 L6_VADJ=3.3 V)。 */
#ifndef BOARD_SD_H
#define BOARD_SD_H
#include "bsp.h"
#include "io.h"
#include "spi.h"
#if defined(PIN_SD_SCK) && !defined(SD_EXTERNAL)
#define SD_SCK_PIN PIN_SD_SCK
#define SD_MOSI_PIN PIN_SD_MOSI
#define SD_MISO_PIN PIN_SD_MISO
#define SD_CS_PIN PIN_SD_CS
#else
#define SD_SCK_PIN PIN_EXT29
#define SD_MOSI_PIN PIN_EXT30
#define SD_MISO_PIN PIN_EXT31
#define SD_CS_PIN PIN_EXT32
#endif
static inline void board_sd_init(void)
{
    io_write(SD_CS_PIN, 1);
    io_connect_out(SD_CS_PIN, SIG_GPIO);
    io_dir(SD_CS_PIN, IO_OUTPUT);
    io_dir(SD_MISO_PIN, IO_INPUT);
    io_connect_out(SD_SCK_PIN, SIG_SPI_SCK);
    io_connect_out(SD_MOSI_PIN, SIG_SPI_MOSI);
    io_connect_in(SIG_SPI_MISO, SD_MISO_PIN);
    if (SPI1->SR & SPI_SR_RXNE)
        (void)SPI1->DR;
}
static inline void board_sd_select(int on)
{
    io_write(SD_CS_PIN, !on);
}
/* 50 MHz /128 = 390625 Hz 初始化; /4 = 12.5 MHz 读。长跳线可改成 /8 (br=2)。 */
static inline void board_sd_speed(int fast)
{
    spi_init(SPI1, 0, fast ? 1 : 6);
}
/* 全双工单字节。每字节都取走 RX, 防止 OVR; 超时返回0。 */
static inline int board_sd_xfer(uint8_t v, uint8_t *r)
{
    uint32_t start = bsp_cycles();
    while (!(SPI1->SR & SPI_SR_TXE))
        if (bsp_cycles() - start > SYSCLK_HZ / 100)
            return 0;
    SPI1->DR = v;
    while (!(SPI1->SR & SPI_SR_RXNE))
        if (bsp_cycles() - start > SYSCLK_HZ / 100)
            return 0;
    *r = (uint8_t)SPI1->DR;
    return 1;
}
#endif
