/* 电脑上的 gfx.h: 画面描述存在内存里 (相当于板上的显示寄存器和显存), render.c 照着画, stats.c 照着数 */
#ifndef GFX_MEM_H
#define GFX_MEM_H

#include "gfx.h"

typedef struct {
    gfx_sprite_t sprites[GFX_SPRITE_MAX];
    uint32_t sprite_n;
    uint32_t dropped; /* 这一帧表满了没加进去的个数 */
    uint16_t backdrop;
    uint16_t map[GFX_MAP_H][GFX_MAP_W];
    int32_t scroll_x, scroll_y;
    int32_t clip0, clip1;
    int32_t window_x, window_y;
    uint8_t window_on;
    char text[GFX_TEXT_ROWS][GFX_TEXT_COLS];
    uint8_t text_color[GFX_TEXT_ROWS][GFX_TEXT_COLS];
} gfx_state_t;

extern gfx_state_t gfx;

#endif
