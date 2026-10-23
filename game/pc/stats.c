/* 硬件要的数: 照精灵表数每条逻辑行 (640x360 的一行) 上有几个对象、要画几个点; 存下有代表性的帧给参考模型。
 * 一个对象在某行要画的宽度 = 它的外框和这一行相交的部分 (透明点也算: 硬件不知道哪里透明, 照样要走一遍)。
 * 旋转的对象外框按边长 x 1.5 算 (转 45 度时对角线是 1.41 倍, 硬件要扫这么大的框, 同 GBA 的 double size)。 */
#include <stdio.h>
#include "assets.h"
#include "gfx_mem.h"
#include "stats.h"

stats_t stats;
static FILE *dump;
static uint32_t frame_no;

/* 对象的外框 (画面坐标, 左闭右开), 裁到画面和游戏区; 完全看不见返回 0 */
static int extent(const gfx_sprite_t *s, int *x0, int *x1, int *y0, int *y1)
{
    if (s->image >= IMG_COUNT)
        return 0;
    int size = assets_images[s->image].size;
    if (s->flags & GFX_AFFINE)
        size = size * s->scale / GFX_SCALE_1 * 3 / 2;
    int left = s->flags & GFX_CLIP ? gfx.clip0 : 0, right = s->flags & GFX_CLIP ? gfx.clip1 : GFX_W;
    *x0 = s->x - size / 2;
    *y0 = s->y - size / 2;
    *x1 = *x0 + size;
    *y1 = *y0 + size;
    *x0 = *x0 < left ? left : *x0;
    *x1 = *x1 > right ? right : *x1;
    *y0 = *y0 < 0 ? 0 : *y0;
    *y1 = *y1 > GFX_H ? GFX_H : *y1;
    return *x0 < *x1 && *y0 < *y1;
}

void stats_open_dump(const char *path)
{
    dump = fopen(path, "w");
    if (!dump) {
        perror(path);
        return;
    }
    /* 第一行: 不随帧变的东西 (图案尺寸、背景图块表、游戏区) */
    fprintf(dump, "{\"images\": [");
    for (int i = 0; i < IMG_COUNT; i++)
        fprintf(dump, "%s%d", i ? ", " : "", assets_images[i].size);
    fprintf(dump, "], \"clip\": [%d, %d], \"map\": [", gfx.clip0, gfx.clip1);
    for (int r = 0; r < GFX_MAP_H; r++)
        for (int c = 0; c < GFX_MAP_W; c++)
            fprintf(dump, "%s%d", r || c ? "," : "", gfx.map[r][c]);
    fprintf(dump, "]}\n");
}

static void write_frame(const char *why)
{
    fprintf(dump, "{\"frame\": %u, \"why\": \"%s\", \"scroll\": [%d, %d], \"fade\": [%d, %d], \"sprites\": [", frame_no, why,
            gfx.scroll_x, gfx.scroll_y, gfx.fade_color, gfx.fade_level);
    for (uint32_t i = 0; i < gfx.sprite_n; i++) {
        const gfx_sprite_t *s = &gfx.sprites[i];
        fprintf(dump, "%s[%d, %d, %d, %d, %d, %d, %d]", i ? ", " : "", s->x, s->y, s->image, s->flags, s->alpha, s->angle,
                s->scale);
    }
    fprintf(dump, "]}\n");
}

void stats_frame(void)
{
    static uint32_t objects[GFX_H], pixels[GFX_H];
    for (int y = 0; y < GFX_H; y++)
        objects[y] = pixels[y] = 0;
    for (uint32_t i = 0; i < gfx.sprite_n; i++) {
        int x0, x1, y0, y1;
        if (!extent(&gfx.sprites[i], &x0, &x1, &y0, &y1))
            continue;
        for (int y = y0; y < y1; y++) {
            objects[y]++;
            pixels[y] += (uint32_t)(x1 - x0);
        }
    }
    stats.line_objects = stats.line_pixels = 0;
    for (int y = 0; y < GFX_H; y++) {
        if (objects[y] > stats.line_objects)
            stats.line_objects = objects[y];
        if (pixels[y] > stats.line_pixels)
            stats.line_pixels = pixels[y];
    }
    stats.sprites = gfx.sprite_n;

    int record = 0;
    if (stats.sprites > stats.max_sprites)
        stats.max_sprites = stats.sprites;
    if (stats.line_objects > stats.max_line_objects)
        stats.max_line_objects = stats.line_objects;
    if (stats.line_pixels > stats.max_line_pixels) {
        stats.max_line_pixels = stats.line_pixels;
        record = 1;
    }
    if (dump && (record || frame_no % 60 == 0))
        write_frame(record ? "max" : "every60");
    frame_no++;
}

void stats_close(void)
{
    if (dump)
        fclose(dump);
    dump = NULL;
}
