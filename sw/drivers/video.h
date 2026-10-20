/* 视频外设: 图块背景 + 精灵, 寄存器见 amarisc.h, 说明见 docs/video.md */
#ifndef VIDEO_DRV_H
#define VIDEO_DRV_H

#include "amarisc.h"

#define VIDEO_W 320
#define VIDEO_H 240
#define VIDEO_MAP_W 64
#define VIDEO_MAP_H 32
#define VIDEO_SPRITE_N 64

/* 调色板 pal 的第 color 色 */
static inline void video_palette(uint32_t pal, uint32_t color, uint16_t rgb565)
{
    VIDEO_PALETTE[pal * 16 + color] = rgb565;
}

/* 图块 n 的 8 行, 每行 8 个 4 位色号, 左起第 i 个在 [4i+3:4i] */
static inline void video_tile(uint32_t n, const uint32_t rows[8])
{
    for (uint32_t i = 0; i < 8; i++)
        VIDEO_TILES[n * 8 + i] = rows[i];
}

/* 背景第 y 行第 x 列放图块 tile, 用调色板 pal */
static inline void video_map(uint32_t x, uint32_t y, uint32_t tile, uint32_t pal)
{
    VIDEO_MAP[y * VIDEO_MAP_W + x] = pal << 8 | tile;
}

static inline void video_sprite(uint32_t n, int32_t x, int32_t y, uint32_t tile, uint32_t pal)
{
    VIDEO_SPRITES[n] = VIDEO_SPRITE(x, y, tile, pal);
}

static inline void video_sprite_hide(uint32_t n)
{
    VIDEO_SPRITES[n] = 0;
}

static inline void video_scroll(uint32_t x, uint32_t y)
{
    VIDEO->SCROLL = (y & 255) << 16 | (x & 511);
}

/* 小窗: 160x120, 显示视觉输入 (摄像头 / HDMI 输入) 缩小后的画面, 盖在最上面; 左上角放在 (x, y) */
static inline void video_window(uint32_t x, uint32_t y)
{
    VIDEO->WINDOW = (y & 255) << 16 | (x & 511);
    VIDEO->CTRL |= VIDEO_CTRL_WINDOW;
}

/* 等到下一帧画完 (进入场消隐), 之后改显存不会撕裂 */
static inline void video_wait_frame(void)
{
    uint32_t frame = VIDEO->FRAME;
    while (VIDEO->FRAME == frame)
        ;
}

#endif
