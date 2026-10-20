#include "app_board.h"

const uint32_t leds[LED_N] = {PIN_LD2_0, PIN_LD2_1, PIN_LD2_2, PIN_LD2_3, PIN_LD2_4, PIN_LD2_5, PIN_LD2_6, PIN_LD2_7};

key_t keys[KEY_N] = {
    {.pin = PIN_S0}, {.pin = PIN_S1}, {.pin = PIN_S2}, {.pin = PIN_S3}, {.pin = PIN_S4},
};

/* 128x160 屏左下, 按板上的十字摆: S0 右, S1 下, S2 中, S3 左, S4 上 */
const struct key_pos key_pos[KEY_N] = {
    {46, 124}, {30, 140}, {30, 124}, {14, 124}, {30, 108},
};
