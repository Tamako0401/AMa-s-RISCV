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
    case 'm':
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

/* pad.py 的 'P' 帧 */
static void frame(pad_t *pad, const link_frame_t *f)
{
    if (f->type != 'P' || f->len != 6)
        return;
    const uint8_t *p = f->data;
    pad->pad_keys = p[0] | (p[1] & 1u) << 7 | (p[1] >> 1 & 1u) << 8 | (p[1] >> 3 & 1u) << 9 | (p[1] >> 4 & 1u) << 10;
    pad->mouse = p[1] >> 2 & 1;
    pad->mx = (int32_t)link_u14(p + 2);
    pad->my = (int32_t)link_u14(p + 4);
}

/* 终端打的一个字 */
static void text(pad_t *pad, uint8_t c)
{
    /* 方向键: ESC [ A/B/C/D */
    if (pad->esc == 2) {
        pad->esc = 0;
        tap(pad, c == 'A' ? PAD_UP : c == 'B' ? PAD_DOWN : c == 'C' ? PAD_RIGHT : c == 'D' ? PAD_LEFT : 0);
    } else if (pad->esc == 1 && c == '[')
        pad->esc = 2;
    else if (pad->esc == 1) { /* ESC 后面跟的不是 '[': ESC 是单按的, 这个字照常处理 */
        pad->esc = 0;
        tap(pad, PAD_MENU);
        text(pad, c);
    } else if (c == 0x1B)
        pad->esc = 1;
    else
        tap(pad, key_of((char)c));
}

void pad_poll(pad_t *pad)
{
    for (uint32_t i = 0; i < sizeof pad->ttl; i++)
        if (pad->ttl[i])
            pad->ttl[i]--;
    /* 单按 Esc: 上一帧收到 ESC 之后整整一帧没再来字节 (方向键的 ESC [ A 是连着来的) */
    int lone_esc = pad->esc == 1;
    char c;
    while (uart_getc(CONSOLE_UART, &c)) {
        int got = link_byte(&pad->link, (uint8_t)c);
        lone_esc = 0;
        if (got == LINK_TEXT)
            text(pad, (uint8_t)c);
        else if (got == LINK_FRAME)
            frame(pad, &pad->link.frame);
    }
    if (lone_esc) {
        pad->esc = 0;
        tap(pad, PAD_MENU);
    }
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
