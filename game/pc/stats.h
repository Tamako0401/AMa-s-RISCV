#ifndef STATS_H
#define STATS_H

#include <stdint.h>

typedef struct {
    /* 这一帧 */
    uint32_t sprites;      /* 精灵表用了几项 */
    uint32_t line_objects; /* 最忙的一行有几个对象 */
    uint32_t line_pixels;  /* 最忙的一行要画几个点 (不含背景) */
    /* 开始以来的最大值 */
    uint32_t max_sprites, max_line_objects, max_line_pixels;
} stats_t;

extern stats_t stats;

/* 存帧: 第一行是不变的东西, 之后每行一帧 (每 60 帧一次, 以及"最忙一行"创新高的帧), JSON */
void stats_open_dump(const char *path);
void stats_frame(void); /* 每帧画完调 */
void stats_close(void);

#endif
