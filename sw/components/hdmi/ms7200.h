/* MS7200 HDMI 接收芯片: 把 HDMI 解码成并行 RGB888 + 同步 + 像素时钟送给 FPGA。
 * 上电写一遍寄存器 (含 EDID, 电脑据此选分辨率); 之后要不断调 ms7200_poll, 输入时钟稳定时补一段设置。 */
#ifndef MS7200_H
#define MS7200_H

#include "i2c.h"

/* 配置芯片 (复位由调用方做); 成功返回 0, 芯片没应答返回 -1 */
int ms7200_init(const i2c_pins_t *i2c);
/* 查输入状态, 输入时钟刚稳定 (接上电脑、换分辨率) 时补写设置; 返回 1 表示这次补写了 */
int ms7200_poll(const i2c_pins_t *i2c);

#endif
