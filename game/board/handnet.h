/* 板上的手: handnet 加速器从 HDMI 输入的 160x120 小图里认手 (sw/nn/nn.h 的 nn_capture: 硬件抓下一帧完整小图,
 * 验证通过后自动推理)。CPU 不等: 每个游戏帧看一眼状态, 出了结果就解码, 马上再抓下一帧。
 * 一次 = 等下一帧小图 (最多 16.7 ms) + 推理 792010 拍 (50 MHz 下约 16 ms), 大约 30 次 / 秒。
 * 没有视频时抓帧一直等着, 就是一直 "没有手"。
 *
 * 坐标: 小图坐标 x4 就是 hand_raw_t 要的 640x480, 方向和小窗里看到的一样 (hand_to_window 按这个画手的位置)。
 * 画面要不要左右镜像由视频源决定 (电脑上的摄像头软件一般已经镜像), 这里不翻。 */
#ifndef HANDNET_H
#define HANDNET_H

#include <stdint.h>
#include "hand.h"

typedef struct {
    uint32_t results; /* 出了几次结果 (hand_raw_t 的 seq) */
    uint32_t errors;  /* 坏帧几次 (尺寸变了、断了一半) */
    uint8_t started;
    uint8_t heat; /* 最近一次的置信度 0..255 (> 127 算找到手), 调试用 */
} handnet_t;

/* 每个游戏帧调一次; 有新结果时写 *raw 并返回 1 */
int handnet_poll(handnet_t *n, hand_raw_t *raw);

#endif
