#include "app_board.h"

const uint32_t leds[LED_N] = {PIN_LED1, PIN_LED2, PIN_LED3, PIN_LED4, PIN_LED5, PIN_LED6, PIN_LED7, PIN_LED8};

key_t keys[KEY_N] = {
    {.pin = PIN_KEY1}, {.pin = PIN_KEY2}, {.pin = PIN_KEY3}, {.pin = PIN_KEY4},
};

/* 240x320 屏左下角排成一行, 和板上按键顺序一致 */
const struct key_pos key_pos[KEY_N] = {
    {20, 260}, {36, 260}, {52, 260}, {68, 260},
};
