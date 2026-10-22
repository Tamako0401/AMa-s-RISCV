/* 用 SDL 照 gfx_mem 画一帧。只求看起来和硬件一样 (最近邻放大、1 位透明、加法混合), 不求逐像素一致:
 * 逐像素一致是以后 Python 参考模型的事。 */
#include <SDL.h>
#include "assets.h"
#include "gfx_mem.h"
#include "render.h"

static SDL_Renderer *renderer;
static SDL_Texture *images[IMG_COUNT];
static SDL_Texture *screen; /* 640x360 的画面 */
static SDL_Texture *output; /* 1280x720 的输出 (放大后的画面 + 文字), 再贴到窗口上 */
static SDL_Texture *font;   /* 128 个字排成一行, 白字透明底 */
static SDL_Texture *camera; /* 摄像头小窗 160x120 */
static int camera_ready;

/* 文字的 16 色 (CGA 调色板) */
static const uint8_t text_rgb[16][3] = {
    {0, 0, 0},       {0, 0, 170},     {0, 170, 0},     {0, 170, 170}, {170, 0, 0},     {170, 0, 170},
    {170, 85, 0},    {170, 170, 170}, {85, 85, 85},    {85, 85, 255}, {85, 255, 85},   {85, 255, 255},
    {255, 85, 85},   {255, 85, 255},  {255, 255, 85}, {255, 255, 255},
};

static uint32_t argb(uint16_t c)
{
    if (c == ASSET_TRANSPARENT)
        return 0;
    uint32_t r = (c >> 11) << 3, g = ((c >> 5) & 63) << 2, b = (c & 31) << 3;
    return 0xFF000000u | r << 16 | g << 8 | b;
}

void render_init(SDL_Renderer *r)
{
    renderer = r;
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0"); /* 放大、旋转都用最近邻, 和硬件一样 */
    for (int i = 0; i < IMG_COUNT; i++) {
        const asset_image_t *a = &assets_images[i];
        uint32_t pixels[64 * 64];
        for (int k = 0; k < a->size * a->size; k++)
            pixels[k] = argb(a->pixels[k]);
        images[i] = SDL_CreateTexture(r, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STATIC, a->size, a->size);
        SDL_UpdateTexture(images[i], NULL, pixels, a->size * 4);
    }

    static uint32_t glyphs[16][128 * 8];
    for (int c = 0; c < 128; c++)
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 8; x++)
                glyphs[y][c * 8 + x] = assets_font[c][y] >> (7 - x) & 1 ? 0xFFFFFFFFu : 0;
    font = SDL_CreateTexture(r, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STATIC, 128 * 8, 16);
    SDL_UpdateTexture(font, NULL, glyphs, 128 * 8 * 4);
    SDL_SetTextureBlendMode(font, SDL_BLENDMODE_BLEND);

    screen = SDL_CreateTexture(r, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, GFX_W, GFX_H);
    output = SDL_CreateTexture(r, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, GFX_W * 2, GFX_H * 2);
    camera = SDL_CreateTexture(r, SDL_PIXELFORMAT_BGR24, SDL_TEXTUREACCESS_STREAMING, GFX_WINDOW_W, GFX_WINDOW_H);
}

void render_camera(const uint8_t *bgr)
{
    SDL_UpdateTexture(camera, NULL, bgr, GFX_WINDOW_W * 3);
    camera_ready = 1;
}

static void set_color565(uint16_t c)
{
    SDL_SetRenderDrawColor(renderer, (c >> 11) << 3, ((c >> 5) & 63) << 2, (c & 31) << 3, 255);
}

static void draw_background(void)
{
    SDL_Rect clip = {gfx.clip0, 0, gfx.clip1 - gfx.clip0, GFX_H};
    SDL_RenderSetClipRect(renderer, &clip);
    /* 画面点 (x, y) 对应背景点 (x + scroll_x, y + scroll_y), 绕回 */
    int sx = gfx.scroll_x & (GFX_MAP_W * 8 - 1), sy = gfx.scroll_y & (GFX_MAP_H * 8 - 1);
    for (int ty = -1; ty <= GFX_H / 8; ty++)
        for (int tx = gfx.clip0 / 8 - 1; tx <= gfx.clip1 / 8; tx++) {
            int mx = (tx + sx / 8) & (GFX_MAP_W - 1), my = (ty + sy / 8) & (GFX_MAP_H - 1);
            SDL_Rect dst = {tx * 8 - sx % 8, ty * 8 - sy % 8, 8, 8};
            SDL_RenderCopy(renderer, images[gfx.map[my][mx]], NULL, &dst);
        }
    SDL_RenderSetClipRect(renderer, NULL);
}

static void draw_sprite(const gfx_sprite_t *s)
{
    if (s->image >= IMG_COUNT)
        return;
    SDL_Texture *t = images[s->image];
    int size = assets_images[s->image].size;
    double angle = 0;
    if (s->flags & GFX_AFFINE) {
        size = size * s->scale / GFX_SCALE_1;
        angle = s->angle * 360.0 / 256;
    }
    SDL_Rect dst = {s->x - size / 2, s->y - size / 2, size, size};
    SDL_Rect clip = {gfx.clip0, 0, gfx.clip1 - gfx.clip0, GFX_H};
    SDL_RenderSetClipRect(renderer, s->flags & GFX_CLIP ? &clip : NULL);
    SDL_SetTextureBlendMode(t, s->flags & GFX_ADD ? SDL_BLENDMODE_ADD : SDL_BLENDMODE_BLEND);
    SDL_SetTextureAlphaMod(t, s->flags & GFX_ALPHA ? s->alpha * 255 / GFX_ALPHA_MAX : 255);
    int flip = (s->flags & GFX_FLIP_X ? SDL_FLIP_HORIZONTAL : 0) | (s->flags & GFX_FLIP_Y ? SDL_FLIP_VERTICAL : 0);
    SDL_RenderCopyEx(renderer, t, NULL, &dst, angle, NULL, (SDL_RendererFlip)flip);
}

void render_frame(const char *shot)
{
    SDL_SetRenderTarget(renderer, screen);
    set_color565(gfx.backdrop);
    SDL_RenderClear(renderer);
    draw_background();
    if (gfx.window_on) {
        SDL_Rect dst = {gfx.window_x, gfx.window_y, GFX_WINDOW_W, GFX_WINDOW_H};
        if (camera_ready) {
            SDL_RenderCopy(renderer, camera, NULL, &dst);
        } else {
            SDL_SetRenderDrawColor(renderer, 40, 40, 40, 255);
            SDL_RenderFillRect(renderer, &dst);
        }
    }
    for (uint32_t i = 0; i < gfx.sprite_n; i++)
        draw_sprite(&gfx.sprites[i]);
    SDL_RenderSetClipRect(renderer, NULL);

    /* 放大 2 倍到 1280x720, 文字层按 1280x720 原生画在上面 */
    SDL_SetRenderTarget(renderer, output);
    SDL_RenderCopy(renderer, screen, NULL, NULL);
    for (int row = 0; row < GFX_TEXT_ROWS; row++)
        for (int col = 0; col < GFX_TEXT_COLS; col++) {
            unsigned char ch = (unsigned char)gfx.text[row][col];
            if (ch <= ' ' || ch >= 128)
                continue;
            const uint8_t *rgb = text_rgb[gfx.text_color[row][col] & 15];
            SDL_SetTextureColorMod(font, rgb[0], rgb[1], rgb[2]);
            SDL_Rect src = {ch * 8, 0, 8, 16}, dst = {col * 8, row * 16, 8, 16};
            SDL_RenderCopy(renderer, font, &src, &dst);
        }
    if (shot) {
        SDL_Surface *s = SDL_CreateRGBSurfaceWithFormat(0, GFX_W * 2, GFX_H * 2, 32, SDL_PIXELFORMAT_ARGB8888);
        SDL_RenderReadPixels(renderer, NULL, SDL_PIXELFORMAT_ARGB8888, s->pixels, s->pitch);
        SDL_SaveBMP(s, shot);
        SDL_FreeSurface(s);
    }
    SDL_SetRenderTarget(renderer, NULL);
    SDL_RenderCopy(renderer, output, NULL, NULL);
    SDL_RenderPresent(renderer);
}
