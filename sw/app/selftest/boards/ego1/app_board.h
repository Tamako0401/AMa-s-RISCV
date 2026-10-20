/* selftest 在 EGO1 上: LD2 一排 8 个 LED, S0~S4 十字形 5 个键 */
#ifndef APP_BOARD_H
#define APP_BOARD_H

#include "ego1_pins.h"
#include "key.h"

#define LED_N 8
#define KEY_N 5

extern const uint32_t leds[LED_N];
extern key_t keys[KEY_N];
/* 每个键在屏幕上的方块左上角 (避开测试图: 色块、对角线) */
extern const struct key_pos {
    uint16_t x, y;
} key_pos[KEY_N];

#endif
