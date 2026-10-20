/* selftest 在盘古上: 8 个 LED, KEY2~KEY8 一排 7 个键 */
#ifndef APP_BOARD_H
#define APP_BOARD_H

#include "mes50hp_pins.h"
#include "key.h"

#define LED_N 8
#define KEY_N 7

extern const uint32_t leds[LED_N];
extern key_t keys[KEY_N];
/* 每个键在屏幕上的方块左上角 (避开测试图: 色块、对角线) */
extern const struct key_pos {
    uint16_t x, y;
} key_pos[KEY_N];

#endif
