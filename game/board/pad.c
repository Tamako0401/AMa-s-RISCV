#include "pad.h"

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

/* pad.py 或手柄板的 'P' 帧 */
static void frame(pad_t *pad, pad_port_t *port, const link_frame_t *f)
{
    if (f->type != 'P') {
        if (pad->on_frame)
            pad->on_frame(f, pad->ctx);
        return;
    }
    if (f->len != 6)
        return;
    const uint8_t *p = f->data;
    port->keys = p[0] | (p[1] & 1u) << 7 | (p[1] >> 1 & 1u) << 8 | (p[1] >> 3 & 1u) << 9 | (p[1] >> 4 & 1u) << 10;
    port->mouse = p[1] >> 2 & 1;
    port->age = 0;
    /* 鼠标位置: 鼠标在窗口里的口优先, 都不在就跟最后一帧 (只有一个口时同原来: 每帧都更新) */
    int other = 0;
    for (uint32_t i = 0; i < PAD_PORTS; i++)
        if (&pad->port[i] != port && pad->port[i].mouse && pad->port[i].age < PAD_STALE)
            other = 1;
    if (port->mouse || !other) {
        pad->mx = (int32_t)link_u14(p + 2);
        pad->my = (int32_t)link_u14(p + 4);
    }
}

/* 终端打的一个字 */
static void text(pad_t *pad, pad_port_t *port, uint8_t c)
{
    /* 方向键: ESC [ A/B/C/D */
    if (port->esc == 2) {
        port->esc = 0;
        tap(pad, c == 'A' ? PAD_UP : c == 'B' ? PAD_DOWN : c == 'C' ? PAD_RIGHT : c == 'D' ? PAD_LEFT : 0);
    } else if (port->esc == 1 && c == '[')
        port->esc = 2;
    else if (port->esc == 1) { /* ESC 后面跟的不是 '[': ESC 是单按的, 这个字照常处理 */
        port->esc = 0;
        tap(pad, PAD_MENU);
        text(pad, port, c);
    } else if (c == 0x1B)
        port->esc = 1;
    else
        tap(pad, key_of((char)c));
}

void pad_begin(pad_t *pad)
{
    for (uint32_t i = 0; i < sizeof pad->ttl; i++)
        if (pad->ttl[i])
            pad->ttl[i]--;
    for (uint32_t i = 0; i < PAD_PORTS; i++) {
        pad_port_t *port = &pad->port[i];
        port->quiet = 1;
        if (port->age < PAD_STALE)
            port->age++;
    }
}

void pad_byte(pad_t *pad, uint32_t n, uint8_t c)
{
    pad_port_t *port = &pad->port[n];
    int got = link_byte(&port->link, c);
    port->quiet = 0;
    if (got == LINK_TEXT)
        text(pad, port, c);
    else if (got == LINK_FRAME)
        frame(pad, port, &port->link.frame);
}

void pad_end(pad_t *pad)
{
    uint32_t keys = 0;
    uint8_t mouse = 0;
    for (uint32_t i = 0; i < PAD_PORTS; i++) {
        pad_port_t *port = &pad->port[i];
        /* 单按 Esc: 上一帧收到 ESC 之后整整一帧没再来字节 (方向键的 ESC [ A 是连着来的) */
        if (port->esc == 1 && port->quiet) {
            port->esc = 0;
            tap(pad, PAD_MENU);
        }
        if (port->age < PAD_STALE) {
            keys |= port->keys;
            mouse |= port->mouse;
        }
    }
    pad->pad_keys = keys;
    pad->mouse = mouse;
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

/* 电脑上的测试只编上面的部分: 没有串口 */
#ifndef PAD_NO_UART
#include "aux_uart.h"
#include "bsp.h"

void pad_poll(pad_t *pad)
{
    static UART_TypeDef *const uarts[PAD_PORTS] = {CONSOLE_UART, AUX_UART};
    pad_begin(pad);
    for (uint32_t i = 0; i < PAD_PORTS; i++) {
        char c;
        while (uart_getc(uarts[i], &c))
            pad_byte(pad, i, (uint8_t)c);
    }
    pad_end(pad);
}
#endif
