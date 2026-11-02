/* 本机按键的小表: X(GPIO 脚, pad.h 的按键位)。其他板先留空, 换板时只改这里。
 * 100HP 的 KEY1~4 低有效, 板级顶层已取反, key_ticks 读到 1 就是按下。 */
#ifndef LOCAL_KEYS_H
#define LOCAL_KEYS_H

#ifdef BOARD_MES2L100HP
#define PAD_LOCAL_KEYS(X) \
    X(PIN_KEY1, PAD_A) \
    X(PIN_KEY2, PAD_MENU) \
    X(PIN_KEY3, PAD_RESTART) \
    X(PIN_KEY4, PAD_SLOW)
#else
#define PAD_LOCAL_KEYS(X)
#endif

#endif
