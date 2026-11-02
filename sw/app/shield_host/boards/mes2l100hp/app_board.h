/* shield_host 在 mes2l100hp 上的接线: 板上 KEY1~KEY4 (KEY0 是复位); 功放、星闪在 GameShield 上 (见 bsp) */
#ifndef APP_BOARD_H
#define APP_BOARD_H

#include "mes2l100hp_pins.h"

#define LED PIN_LED1
#define KEYS {PIN_KEY1, PIN_KEY2, PIN_KEY3, PIN_KEY4}

#endif
