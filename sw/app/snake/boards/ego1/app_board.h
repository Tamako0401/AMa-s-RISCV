/* snake 在 EGO1 上的接线: 十字形 5 个键, 设置用拨码开关 */
#ifndef APP_BOARD_H
#define APP_BOARD_H

#include "ego1_pins.h"
#include "key.h"

enum { K_UP, K_DOWN, K_LEFT, K_RIGHT, K_START, KEY_N };
extern key_t keys[KEY_N];

#define LED_WRAP PIN_LD2_0 /* 挨着拨码开关 SW0 */
#define LED_UART PIN_LD2_1
#define SW_WRAP PIN_SW0
#define SW_UART PIN_SW1

/* 穿墙、串口控制两个开关: EGO1 读拨码开关 (拨上 = 开) */
void read_settings(int *uart_on, int *wrap);

#endif
