/* MS7210 HDMI 发送芯片: FPGA 送并行 RGB888 + 同步 + 像素时钟, 芯片编码成 HDMI。
 * 上电要经 I2C 写一遍寄存器才出图。 */
#ifndef MS7210_H
#define MS7210_H

#include "i2c.h"

typedef struct {
    i2c_pins_t i2c;
    uint32_t rst; /* 复位, 低有效 */
} ms7210_pins_t;

/* 复位并配置芯片; 成功返回 0, 芯片没应答返回 -1 */
int ms7210_init(const ms7210_pins_t *pins);

#endif
