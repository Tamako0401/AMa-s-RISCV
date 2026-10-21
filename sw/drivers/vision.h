/* 视觉输入: 颜色跟踪, 寄存器见 amarisc.h, 说明见 docs/vision.md */
#ifndef VISION_DRV_H
#define VISION_DRV_H

#include "amarisc.h"

#define VISION_W 160
#define VISION_H 120

/* 跟踪的颜色 (YCbCr 的 Cb, Cr) 和容差; 颜色可以用 model/color.py 在画面上点选得到 */
static inline void vision_color(uint32_t cb, uint32_t cr, uint32_t tol)
{
    VISION->COLOR = (tol & 255) << 16 | (cr & 255) << 8 | (cb & 255);
}

/* 上一帧的标记位置 (160x120 里的重心); 命中点少于 min_points 返回 0 (没找到) */
static inline int vision_find(uint32_t min_points, uint32_t *x, uint32_t *y)
{
    uint32_t frame, n, sx, sy;
    do { /* 读的途中出了新结果就重读, 三个数要来自同一帧 */
        frame = VISION->FRAME;
        n = VISION->COUNT;
        sx = VISION->SUM_X;
        sy = VISION->SUM_Y;
    } while (VISION->FRAME != frame);
    if (n == 0 || n < min_points)
        return 0;
    *x = sx / n;
    *y = sy / n;
    return 1;
}

#endif
