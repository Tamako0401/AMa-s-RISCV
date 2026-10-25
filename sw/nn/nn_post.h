/* 把 300 个格子解码成手心位置和握拳: 全是整数, 表在 nn_tables.h (脚本生成)。
 *
 * 网络的输出每格 4 个 int8 logit: 热力图、格内 dx、格内 dy、握拳。
 * 热力图取最大的一格; 分数 > NN_HEAT_Z 等价于 sigmoid > 0.5, 算找到手。
 * 手心 = (格子 + 格内偏移) * 8, 落在 160x120 的画面上。 */
#ifndef NN_POST_H
#define NN_POST_H

#include <stdint.h>

#include "nn.h"

typedef struct {
    int found;     /* 1 = 找到手 */
    uint32_t cell; /* 热力图最大的格子号 (0..NN_OUT_WORDS-1) */
    uint32_t x, y; /* 手心, 160x120 坐标 */
    int fist;      /* 1 握拳, 0 张开 */
    uint32_t heat; /* 0..255 的热力图概率 */
} nn_hand_t;

static inline void nn_decode(nn_hand_t *h)
{
    uint32_t best = 0;
    int32_t best_q = -128;
    for (uint32_t i = 0; i < NN_OUT_WORDS; i++) {
        int32_t q = (int8_t)(nn_out_word(i) & 255);
        if (q > best_q) {
            best_q = q;
            best = i;
        }
    }
    uint32_t w = nn_out_word(best);
    uint32_t dx = nn_sigmoid_lut[(w >> 8) & 255];
    uint32_t dy = nn_sigmoid_lut[(w >> 16) & 255];
    uint32_t g = nn_sigmoid_lut[(w >> 24) & 255];

    h->cell = best;
    h->heat = nn_sigmoid_lut[(uint8_t)best_q];
    h->found = best_q > NN_HEAT_Z;
    h->x = (best % NN_OUT_W) * 8 + (dx * 8 + 127) / 255;
    h->y = (best / NN_OUT_W) * 8 + (dy * 8 + 127) / 255;
    h->fist = g >= 128;
}

#endif
