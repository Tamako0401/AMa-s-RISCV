/* GPIO 外设驱动 */
#ifndef GPIO_H
#define GPIO_H

#include "amarisc.h"

#define GPIO_PIN(n)  (0x1UL << (n))

static inline void gpio_set(GPIO_TypeDef *gpio, uint32_t pins)   { gpio->BSRR = pins; }
static inline void gpio_reset(GPIO_TypeDef *gpio, uint32_t pins) { gpio->BSRR = pins << 16; }

/* 把 pins 中的每个引脚设为 mode, 其余引脚不变 */
static inline void gpio_set_mode(GPIO_TypeDef *gpio, uint32_t pins, uint32_t mode)
{
    uint32_t ctrl = gpio->CTRL;
    for (uint32_t n = 0; n < 16; n++) {
        if (pins & GPIO_PIN(n))
            ctrl = (ctrl & ~(0x3UL << (2 * n))) | (mode << (2 * n));
    }
    gpio->CTRL = ctrl;
}

#endif
