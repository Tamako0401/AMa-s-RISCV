/* SPI 外设驱动 */
#ifndef SPI_H
#define SPI_H

#include "amarisc.h"

/* mode: 0~3, 即 (CPOL << 1) | CPHA. br: 0~7, SCK = clk / 2^(br+1) */
void spi_init(SPI_TypeDef *spi, uint32_t mode, uint32_t br);
void spi_write_byte(SPI_TypeDef *spi, uint8_t data);
void spi_write(SPI_TypeDef *spi, const uint8_t *buf, uint32_t len);
/* 等最后一个字节真正发完. 改 DC 或释放 CS 前必须调用 */
void spi_wait_idle(SPI_TypeDef *spi);

#endif
