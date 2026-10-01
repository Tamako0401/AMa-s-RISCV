/* 板级支持: 时钟、延时、外部器件接线. 换板子只改这一层. */
#ifndef BSP_H
#define BSP_H

#include <stdint.h>
#include "amarisc.h"
#include "gpio.h"

#define SYSCLK_HZ  50000000UL    /* MES50HP 板载 50MHz, 不经 PLL */

/* 屏幕接线: SPI1 + GPIO 0/1/2, 与 rtl/soc_top/soc_top.v 一致 */
#define LCD_SPI         SPI1
#define LCD_CS_N_PIN    GPIO_PIN(0)
#define LCD_DC_PIN      GPIO_PIN(1)
#define LCD_RST_N_PIN   GPIO_PIN(2)

void delay_ms(uint32_t ms);

#endif
