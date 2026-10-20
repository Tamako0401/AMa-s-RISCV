/* snake 在盘古上的接线: 一排 7 个键, 上下左右是 snake 自己规定的 */
#ifndef APP_BOARD_H
#define APP_BOARD_H

#include "mes50hp_pins.h"
#include "key.h"

enum { K_UP, K_DOWN, K_LEFT, K_RIGHT, K_START, K_UART, K_WRAP, KEY_N };
extern key_t keys[KEY_N];

#define LED_UART PIN_LED3           /* 灯号和按键号一致 */
#define LED_WRAP PIN_LED4

/* 穿墙、串口控制两个开关: 盘古每按一下键切换 */
void read_settings(int *uart_on, int *wrap);

#endif
