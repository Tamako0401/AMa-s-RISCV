/* 软件 I2C 主机: SCL、SDA 是 GPIO 矩阵的普通引脚, 速度由 half_cycles (半个 SCL 周期的时钟数) 定。
 * SCL 推挽输出; SDA 写时输出, 读和等 ACK 时放开 (板上 HDMI 芯片的接法, 同厂商例程)。
 * 寄存器地址 16 位、数据 8 位 (MS7210、OV5640 都是这种)。 */
#ifndef I2C_H
#define I2C_H

#include <stdint.h>

typedef struct {
    uint32_t scl, sda;
    uint32_t half_cycles; /* 例: 50 MHz 下 100 kHz 为 250 */
} i2c_pins_t;

void i2c_init(const i2c_pins_t *pins);
/* dev 是 8 位写地址 (如 0xB2); 成功返回 0, 没有 ACK 返回 -1 */
int i2c_write_reg16(const i2c_pins_t *pins, uint8_t dev, uint16_t reg, uint8_t value);
int i2c_read_reg16(const i2c_pins_t *pins, uint8_t dev, uint16_t reg, uint8_t *value);

#endif
