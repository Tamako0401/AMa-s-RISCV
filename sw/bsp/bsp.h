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

/* 板载 8 个 LED 接 GPIO 8~15; 调试串口 (板载 USB-UART) */
#define LED_PINS        (0xFFUL << 8)
#define LED_SHIFT       8
#define CONSOLE_UART    UART1

void delay_ms(uint32_t ms);
/* 自上电以来的时钟周期数 (32 位, 50MHz 下约 85 秒回绕, 用减法比较即可) */
uint32_t bsp_cycles(void);
/* 毫秒换算成周期数; 仿真构建 (SIM_CYCLE_DIV) 时同比例缩小 */
uint32_t bsp_ms_to_cycles(uint32_t ms);

#endif
