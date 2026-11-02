/* 画面接口: 游戏只通过这里描述画面, 不自己画点。
 * 电脑上 pc/ 用 SDL 照这张表画; 板上就是写显示寄存器。所以这里有什么功能, 硬件就要做什么 (见 game/README.md)。
 *
 * 画面 640x360 (输出 720p 时每点放大成 2x2), 从下到上:
 *   底色 -> 背景 (8x8 图块拼成, 可卷动, 只在游戏区内显示) -> 摄像头小窗 -> 精灵 -> 整体混色 -> 文字 (1280x720 原生,
 * 8x16 一格) 小窗在精灵下面: 可以在小窗上用精灵标出手的位置。 精灵每帧重来: gfx_begin 清空, gfx_sprite 一个个追加,
 * 后加的盖住先加的。背景、文字、小窗改了才写, 一直保留。 */
#ifndef GFX_API_H
#define GFX_API_H

#include <stdint.h>

#define GFX_W 640
#define GFX_H 360
#define GFX_SPRITE_MAX 1024 /* 表的容量; 实际一帧用了多少看统计, 硬件按需要定 */
#define GFX_MAP_W 64        /* 背景图块表 64x64 格 (512x512 点), 卷动时绕回 */
#define GFX_MAP_H 64
#define GFX_TEXT_COLS 160 /* 文字层 1280x720, 每格 8x16 */
#define GFX_TEXT_ROWS 45
#define GFX_WINDOW_W 160 /* 摄像头小窗, 视觉输入缩小后的画面 */
#define GFX_WINDOW_H 120

/* 精灵的 flags */
#define GFX_ALPHA 0x01 /* 半透明, 透明度看 alpha */
#define GFX_ADD 0x02   /* 加法混合 (发光): 颜色加到底下, 黑色等于没画 */
#define GFX_FLIP_X 0x04
#define GFX_FLIP_Y 0x08
#define GFX_AFFINE 0x10 /* 旋转缩放, 看 angle 和 scale */
#define GFX_CLIP 0x20   /* 只在游戏区 (gfx_clip) 内显示: 弹幕飞出游戏区不会盖到侧栏上 */

#define GFX_ALPHA_MAX 16 /* alpha = 16 不透明 */
#define GFX_SCALE_1 16   /* scale = 16 原大 */

typedef struct {
    int16_t x, y;   /* 中心位置, 可以在画面外 */
    uint16_t image; /* 图案编号 (build/assets.h 的 IMG_*); 图案是 8/16/32/64 的正方形, 像素只有透明 / 不透明 */
    uint8_t flags;
    uint8_t alpha; /* 0~16, GFX_ALPHA 时有效 */
    uint8_t angle; /* 一圈 256, GFX_AFFINE 时有效 */
    uint8_t scale; /* 16 = 原大, GFX_AFFINE 时有效 */
} gfx_sprite_t;

/* 文字颜色 (16 色固定调色板) */
enum {
    GFX_BLACK,
    GFX_BLUE,
    GFX_GREEN,
    GFX_CYAN,
    GFX_RED,
    GFX_MAGENTA,
    GFX_BROWN,
    GFX_LIGHT_GRAY,
    GFX_GRAY,
    GFX_LIGHT_BLUE,
    GFX_LIGHT_GREEN,
    GFX_LIGHT_CYAN,
    GFX_LIGHT_RED,
    GFX_PINK,
    GFX_YELLOW,
    GFX_WHITE,
};

/* SD 立绘: 先 load (改了才读/写), 每帧 portrait (左上角, alpha 0~16)。无素材不画。id<0 隐藏。 */
int gfx_portrait_load(int32_t id);
int gfx_portrait_ready(void);
void gfx_portrait(int32_t x, int32_t y, uint32_t alpha);

void gfx_begin(void); /* 开始新的一帧: 清空精灵表 */
/* 追加一个精灵, 返回它以便再设 flags 等; 表满了返回一个不显示的占位, 照样能写 */
gfx_sprite_t *gfx_sprite(int32_t x, int32_t y, uint32_t image);

void gfx_backdrop(uint16_t rgb565);                     /* 底色 */
void gfx_map(int32_t col, int32_t row, uint32_t image); /* 背景第 row 行第 col 列放 8x8 图案 image */
void gfx_scroll(int32_t x, int32_t y);                  /* 背景卷动 */
void gfx_clip(int32_t x0, int32_t x1);                  /* 游戏区 x0 <= x < x1: 背景和带 GFX_CLIP 的精灵只在这里显示 */
void gfx_window(int32_t x, int32_t y);                  /* 摄像头小窗左上角 */
/* 整个画面 (文字除外) 往一个颜色混: level 0 不变, 16 全是这个颜色。闪白、淡入淡出用; 每帧要设 */
void gfx_fade(uint16_t rgb565, uint32_t level);

void gfx_text_clear(void);
void gfx_text(int32_t col, int32_t row, uint32_t color, const char *s);
/* 右对齐写一个非负整数, 占 width 格 */
void gfx_number(int32_t col, int32_t row, uint32_t color, uint32_t n, int32_t width);

#endif
