/* MS7210 HDMI 发送芯片: FPGA 送并行 RGB888 + 同步 + 像素时钟, 芯片编码成 HDMI。
 * 上电要经 I2C 写一遍寄存器才出图。 */
#ifndef MS7210_H
#define MS7210_H

#include "i2c.h"

/* 配置芯片 (复位由调用方做); 成功返回 0, 芯片没应答返回 -1 */
int ms7210_init(const i2c_pins_t *i2c);

#endif
