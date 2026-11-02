/* shield_pad 在 mes50hp 上的接线: GameShield PAD 版用 40P 排线连 J8 (针号和扩展板 J1 一样, 见
 * ~/hw/game-shield/SPEC.md)。 按键和摇杆都是按下接地, 扩展板上有 10k 上拉。顺序: 上 下 左 右 A B SLOW RESTART MENU,
 * 摇杆 上 下 左 右。 */
#ifndef APP_BOARD_H
#define APP_BOARD_H

#include "mes50hp_pins.h"

#define PAD_KEY_PINS {PIN_J8_3, PIN_J8_4, PIN_J8_5, PIN_J8_6, PIN_J8_7, PIN_J8_8, PIN_J8_9, PIN_J8_10, PIN_J8_11}
#define PAD_JOY_PINS {PIN_J8_12, PIN_J8_13, PIN_J8_14, PIN_J8_15}
#define LED PIN_LED1

#endif
