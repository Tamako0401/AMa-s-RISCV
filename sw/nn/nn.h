/* handnet 加速器驱动 (0x4000_6000), 寄存器见 docs/nn.md。
 *
 * 一次推理 = 送一张 160x120 的 RGB888 图 -> 启动 -> 等完成 -> 读 300 个格子。
 * 硬件做的是 model/handnet.py 那张网络的 int8 定点版本, 结果和 model/nnref.py 逐字节相同。
 *
 * 用法:
 *     uint8_t frame[160 * 120 * 3];          // 行优先的 RGB888
 *     nn_load(frame);
 *     nn_start();
 *     nn_wait(1000000);
 *     nn_hand_t h;
 *     nn_decode(&h);                          // 手心位置 + 握拳
 */
#ifndef NN_DRV_H
#define NN_DRV_H

#include <stdint.h>

#include "amarisc.h"
#include "nn_tables.h"

#define NN_IN_W 160
#define NN_IN_H 120
#define NN_IN_BYTES (NN_IN_W * NN_IN_H * 3)

#define NN_CTRL_CAPTURE (1u << 2)
#define NN_STATUS_CAPTURE (1u << 2)
#define NN_STATUS_CAPTURE_ERROR (1u << 3)

/* 把整张图送进输入 RAM。硬件负责 BGR 排序和 q = pixel - 128 的定点化。 */
static inline void nn_load(const uint8_t *rgb)
{
    NN->IN_ADDR = 0;
    for (uint32_t i = 0; i < NN_IN_W * NN_IN_H; i++) {
        const uint8_t *p = rgb + i * 3;
        NN->IN = (uint32_t)p[0] << 16 | (uint32_t)p[1] << 8 | p[2];
    }
}

/* 只写一个像素 (地址自增), 自己算像素序号时用 */
static inline void nn_put(uint32_t r, uint32_t g, uint32_t b)
{
    NN->IN = (r & 255) << 16 | (g & 255) << 8 | (b & 255);
}

static inline void nn_start(void)
{
    NN->CTRL = NN_CTRL_START;
}

/* 抓下一个完整输入帧, 验证通过后自动推理。忙时忽略。 */
static inline void nn_capture(void)
{
    NN->CTRL = NN_CTRL_CAPTURE;
}

static inline int nn_capturing(void)
{
    return (NN->STATUS & NN_STATUS_CAPTURE) != 0;
}

/* 等抓帧及推理; -2 表示坏帧, -1 表示超时。 */
static inline int nn_capture_wait(uint32_t limit)
{
    while (limit--) {
        uint32_t status = NN->STATUS;
        if (status & NN_STATUS_CAPTURE_ERROR)
            return -2;
        if (status & NN_STATUS_DONE)
            return 0;
    }
    return -1;
}

/* 等一次推理结束。limit 是轮询次数; 返回 0 完成, -1 超时 */
static inline int nn_wait(uint32_t limit)
{
    while (limit--) {
        if (NN->STATUS & NN_STATUS_DONE)
            return 0;
    }
    return -1;
}

static inline int nn_busy(void)
{
    return (NN->STATUS & NN_STATUS_BUSY) != 0;
}

static inline uint32_t nn_layer(void)
{
    return (NN->STATUS >> NN_STATUS_LAYER_Pos) & 15;
}

/* 第 cell 个格子的 4 个 int8: [7:0] 热力图, [15:8] dx, [23:16] dy, [31:24] 握拳 */
static inline uint32_t nn_out_word(uint32_t cell)
{
    NN->OUT_ADDR = cell;
    return NN->OUT;
}

/* 输出 300 个字的 FNV-1a 校验 (只算每个格子前 4 个通道), 和 model/nnref.py 的 checksum 一致 */
static inline uint32_t nn_checksum(void)
{
    uint32_t h = 2166136261UL;
    for (uint32_t i = 0; i < NN_OUT_WORDS; i++) {
        uint32_t w = nn_out_word(i);
        for (uint32_t k = 0; k < 4; k++) {
            h = (h ^ ((w >> (k * 8)) & 255)) * 16777619UL;
        }
    }
    return h;
}

#endif
