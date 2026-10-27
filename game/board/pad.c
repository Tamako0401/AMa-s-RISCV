#include "pad.h"
#include "bsp.h"
#include "uart.h"

static uint32_t key_of(char c)
{
    switch (c) {
    case 'w':
        return PAD_UP;
    case 's':
        return PAD_DOWN;
    case 'a':
        return PAD_LEFT;
    case 'd':
        return PAD_RIGHT;
    case 'W':
        return PAD_UP | PAD_SLOW;
    case 'S':
        return PAD_DOWN | PAD_SLOW;
    case 'A':
        return PAD_LEFT | PAD_SLOW;
    case 'D':
        return PAD_RIGHT | PAD_SLOW;
    case 'j':
    case ' ':
    case '\r':
    case '\n':
        return PAD_A;
    case 'k':
        return PAD_B;
    case 'r':
        return PAD_RESTART;
    case 'q':
        return PAD_MENU;
    default:
        return 0;
    }
}

/* 终端来的一个 (或几个, 如 'W' = 上 + 慢) 键: 按住 PAD_HOLD 帧 */
static void tap(pad_t *pad, uint32_t keys)
{
    for (uint32_t i = 0; i < sizeof pad->ttl; i++)
        if (keys >> i & 1)
            pad->ttl[i] = PAD_HOLD;
}

static void byte(pad_t *pad, uint8_t c)
{
    if (c & 0x80) { /* pad.py 的包头 */
        pad->packet[0] = c;
        pad->packet_n = 1;
        return;
    }
    if (pad->packet_n) {
        pad->packet[pad->packet_n++] = c;
        if (pad->packet_n == sizeof pad->packet) {
            const uint8_t *p = pad->packet;
            pad->pad_keys = (p[0] & 0x7Fu) | (p[1] & 1u) << 7 | (p[1] >> 1 & 1u) << 8 | (p[1] >> 3 & 1u) << 9;
            pad->mouse = p[1] >> 2 & 1;
            pad->mx = p[2] << 7 | p[3];
            pad->my = p[4] << 7 | p[5];
            pad->packet_n = 0;
        }
        return;
    }
    /* 方向键: ESC [ A/B/C/D */
    if (pad->esc == 2) {
        pad->esc = 0;
        tap(pad, c == 'A' ? PAD_UP : c == 'B' ? PAD_DOWN : c == 'C' ? PAD_RIGHT : c == 'D' ? PAD_LEFT : 0);
    } else if (pad->esc == 1)
        pad->esc = c == '[' ? 2 : 0;
    else if (c == 0x1B)
        pad->esc = 1;
    else
        tap(pad, key_of((char)c));
}

void pad_poll(pad_t *pad)
{
    for (uint32_t i = 0; i < sizeof pad->ttl; i++)
        if (pad->ttl[i])
            pad->ttl[i]--;
    char c;
    while (uart_getc(CONSOLE_UART, &c))
        byte(pad, (uint8_t)c);
    uint32_t held = pad->pad_keys;
    for (uint32_t i = 0; i < sizeof pad->ttl; i++)
        if (pad->ttl[i])
            held |= 1u << i;
    /* 重开、回标题只要按下那一下: 终端的这两个键不算按住 */
    pad->pressed = held & ~pad->last;
    pad->held = held;
    pad->last = held;
    pad->ttl[7] = pad->ttl[8] = 0;
}
