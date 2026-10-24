/* 板上的 HDMI: 盘古有发送芯片 MS7210 和接收芯片 MS7200, 视频口由板顶层直连,
 * I2C 和复位经 GPIO 矩阵。MES50HP 是两条独立 I2C; MES2L100HP 两颗芯片共用一条
 * (地址 0xB2/0x56 不同, 不冲突), 按 PIN_HDMI_RX_SCL 是否定义区分。 */
#ifndef BOARD_HDMI_H
#define BOARD_HDMI_H

#include "bsp.h"

#ifdef BOARD_EGO1
static inline int board_hdmi_init(void)
{
    return -1;
}
static inline void board_hdmi_poll(void)
{
}
#else
#include "io.h"
#include "ms7200.h"
#include "ms7210.h"

/* 复位并配置两颗芯片; 返回 0 都成功, bit0 = 发送芯片没应答, bit1 = 接收芯片没应答。之后开 VIDEO->CTRL 就出图 */
#ifdef PIN_HDMI_RX_SCL

static const i2c_pins_t board_hdmi_tx = {.scl = PIN_HDMI_SCL, .sda = PIN_HDMI_SDA, .half_cycles = SYSCLK_HZ / 200000};
static const i2c_pins_t board_hdmi_rx = {
    .scl = PIN_HDMI_RX_SCL, .sda = PIN_HDMI_RX_SDA, .half_cycles = SYSCLK_HZ / 200000};

static inline int board_hdmi_init(void)
{
    io_write(PIN_HDMI_RSTN, 0);
    io_dir(PIN_HDMI_RSTN, IO_OUTPUT);
    i2c_init(&board_hdmi_tx);
    i2c_init(&board_hdmi_rx);
    delay_ms(1);
    io_write(PIN_HDMI_RSTN, 1);
    delay_ms(1);
    return (ms7210_init(&board_hdmi_tx) ? 1 : 0) | (ms7200_init(&board_hdmi_rx) ? 2 : 0);
}

/* 主循环里经常调: 电脑接上或换分辨率时给接收芯片补设置 */
static inline void board_hdmi_poll(void)
{
    ms7200_poll(&board_hdmi_rx);
}

#else

static const i2c_pins_t board_hdmi_i2c = {.scl = PIN_HDMI_SCL, .sda = PIN_HDMI_SDA, .half_cycles = SYSCLK_HZ / 200000};

static inline int board_hdmi_init(void)
{
    io_write(PIN_HDMI_RSTN, 0);
    io_dir(PIN_HDMI_RSTN, IO_OUTPUT);
    i2c_init(&board_hdmi_i2c);
    delay_ms(1);
    io_write(PIN_HDMI_RSTN, 1);
    delay_ms(1);
    return (ms7210_init(&board_hdmi_i2c) ? 1 : 0) | (ms7200_init(&board_hdmi_i2c) ? 2 : 0);
}

static inline void board_hdmi_poll(void)
{
    ms7200_poll(&board_hdmi_i2c);
}

#endif
#endif

#endif
