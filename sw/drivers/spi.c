#include "spi.h"

void spi_init(SPI_TypeDef *spi, uint32_t mode, uint32_t br)
{
    spi->CR1 = (mode & (SPI_CR1_CPOL | SPI_CR1_CPHA))
             | ((br << SPI_CR1_BR_Pos) & SPI_CR1_BR)
             | SPI_CR1_MSTR
             | SPI_CR1_SPE;
}

void spi_write_byte(SPI_TypeDef *spi, uint8_t data)
{
    while (!(spi->SR & SPI_SR_TXE))
        ;
    spi->DR = data;
}

void spi_write(SPI_TypeDef *spi, const uint8_t *buf, uint32_t len)
{
    while (len--)
        spi_write_byte(spi, *buf++);
}

void spi_wait_idle(SPI_TypeDef *spi)
{
    while (spi->SR & SPI_SR_BSY)
        ;
}
