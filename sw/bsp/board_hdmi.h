/* 板上的 HDMI 输出: 盘古是 MS7210 (I2C 和复位经 GPIO 矩阵, 视频数据线由 mes50hp_top 直连);
 * EGO1 没有 HDMI。 */
#ifndef BOARD_HDMI_H
#define BOARD_HDMI_H

#include "bsp.h"

#ifdef BOARD_EGO1
static inline int board_hdmi_init(void)
{
    return -1;
}
#else
#include "ms7210.h"
/* 配置发送芯片; 成功返回 0。之后开 VIDEO->CTRL 就出图 */
static inline int board_hdmi_init(void)
{
    static const ms7210_pins_t pins = {.i2c = {.scl = PIN_HDMI_SCL, .sda = PIN_HDMI_SDA}, .rst = PIN_HDMI_RSTN};
    return ms7210_init(&pins);
}
#endif

#endif
