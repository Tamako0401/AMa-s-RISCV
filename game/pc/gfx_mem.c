#include "gfx_mem.h"

gfx_state_t gfx = {.clip1 = GFX_W};
static gfx_sprite_t spare; /* 表满时给的占位 */

void gfx_begin(void)
{
    gfx.sprite_n = 0;
    gfx.dropped = 0;
    gfx.fade_level = 0;
}

gfx_sprite_t *gfx_sprite(int32_t x, int32_t y, uint32_t image)
{
    gfx_sprite_t *s = &spare;
    if (gfx.sprite_n < GFX_SPRITE_MAX)
        s = &gfx.sprites[gfx.sprite_n++];
    else
        gfx.dropped++;
    *s = (gfx_sprite_t){.x = (int16_t)x, .y = (int16_t)y, .image = (uint16_t)image, .alpha = GFX_ALPHA_MAX, .scale = GFX_SCALE_1};
    return s;
}

void gfx_backdrop(uint16_t rgb565)
{
    gfx.backdrop = rgb565;
}

void gfx_map(int32_t col, int32_t row, uint32_t image)
{
    gfx.map[row & (GFX_MAP_H - 1)][col & (GFX_MAP_W - 1)] = (uint16_t)image;
}

void gfx_scroll(int32_t x, int32_t y)
{
    gfx.scroll_x = x;
    gfx.scroll_y = y;
}

void gfx_clip(int32_t x0, int32_t x1)
{
    gfx.clip0 = x0;
    gfx.clip1 = x1;
}

void gfx_window(int32_t x, int32_t y)
{
    gfx.window_x = x;
    gfx.window_y = y;
    gfx.window_on = 1;
}

void gfx_fade(uint16_t rgb565, uint32_t level)
{
    gfx.fade_color = rgb565;
    gfx.fade_level = (uint8_t)(level < 16 ? level : 16);
}

void gfx_text_clear(void)
{
    for (int32_t r = 0; r < GFX_TEXT_ROWS; r++)
        for (int32_t c = 0; c < GFX_TEXT_COLS; c++)
            gfx.text[r][c] = ' ';
}

void gfx_text(int32_t col, int32_t row, uint32_t color, const char *s)
{
    if (row < 0 || row >= GFX_TEXT_ROWS)
        return;
    for (; *s && col < GFX_TEXT_COLS; s++, col++) {
        if (col < 0)
            continue;
        gfx.text[row][col] = *s;
        gfx.text_color[row][col] = (uint8_t)color;
    }
}

void gfx_number(int32_t col, int32_t row, uint32_t color, uint32_t n, int32_t width)
{
    char buf[12];
    int32_t i = width < 11 ? width : 11;
    buf[i] = 0;
    do {
        buf[--i] = (char)('0' + n % 10);
        n /= 10;
    } while (n && i > 0);
    while (i > 0)
        buf[--i] = ' ';
    gfx_text(col, row, color, buf);
}
