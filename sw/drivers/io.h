#ifndef IO_H
#define IO_H

#include "amarisc.h"

#define IO_INPUT 0
#define IO_OUTPUT 1
#define SIG_GPIO 0
#define SIG_UART_TX 1
#define SIG_SPI_SCK 2
#define SIG_SPI_MOSI 3
#define SIG_UART2_TX 4
#define SIG_UART_RX 0
#define SIG_SPI_MISO 1
#define SIG_UART2_RX 2
#define IO_NONE 0xFF /* io_connect_in 的引脚: 不接, 输入信号给空闲电平 */

static inline void io_dir(uint32_t pin, uint32_t dir)
{
    if (dir)
        IO_MATRIX->ENABLE_W1TS[pin >> 5] = 1UL << (pin & 31);
    else
        IO_MATRIX->ENABLE_W1TC[pin >> 5] = 1UL << (pin & 31);
}

static inline void io_write(uint32_t pin, int level)
{
    if (level)
        IO_MATRIX->OUT_W1TS[pin >> 5] = 1UL << (pin & 31);
    else
        IO_MATRIX->OUT_W1TC[pin >> 5] = 1UL << (pin & 31);
}

static inline int io_read(uint32_t pin)
{
    return (IO_MATRIX->IN[pin >> 5] >> (pin & 31)) & 1;
}

static inline void io_connect_out(uint32_t pin, uint32_t sig)
{
    IO_MATRIX->FUNC_OUT_SEL[pin] = sig;
}

static inline void io_connect_in(uint32_t sig, uint32_t pin)
{
    IO_MATRIX->FUNC_IN_SEL[sig] = pin;
}

#endif
