/* 手的输入: 视觉给的原始结果 (摄像头坐标、握拳 / 张开) -> 游戏区坐标和防抖后的手势。
 * 照 model/play.py 的 Hand: 有效区映射、One Euro 平滑、连续 3 帧才切换手势。全部整数运算, 板上照用。 */
#ifndef HAND_H
#define HAND_H

#include <stdint.h>

#define HAND_CAM_W 640 /* 原始坐标的范围: 640x480 的摄像头画面 (已镜像) */
#define HAND_CAM_H 480
/* 有效区: 摄像头画面中间这么大映射到整个游戏区, 手不用伸到画面边上。
 * 高取 60% (同 play.py), 宽按游戏区的宽高比, 横竖放大倍数一样 (1.25):
 * 东方式 320x360 -> 256x288, 水果忍者 640x360 -> 512x288 */
#define HAND_ACTIVE_H 288

/* 视觉每出一帧结果给一次; seq 变了才算新结果 */
typedef struct {
    uint32_t seq;
    int8_t found; /* 找到手没有 */
    int8_t fist;  /* 1 握拳, 0 张开, -1 说不清 */
    int16_t x, y; /* 手心, 摄像头坐标 */
} hand_raw_t;

typedef struct {
    /* 输出 */
    int32_t x, y;   /* 游戏区坐标, Q8; 没手时保持上次的位置 */
    uint8_t valid;  /* 出现过手, x, y 有意义 */
    uint8_t found;  /* 最近一次结果有手 */
    uint8_t fist;   /* 防抖之后 */
    uint8_t opened; /* 这一帧刚从握拳变成张开 (放 bomb) */
    /* 内部 */
    uint32_t seq;
    uint32_t since;    /* 距上次新结果几帧 (游戏帧, 60 帧/秒) */
    uint32_t lost;     /* 连续几帧没手 */
    uint8_t streak;    /* 连续几次是和 fist 相反的手势 */
    uint8_t filtering; /* 平滑器里有旧值 */
    int32_t fx, fy;    /* 平滑后的位置, Q8 */
    int32_t sx, sy;    /* 平滑后的速度, Q8 像素 / 秒 */
} hand_t;

void hand_init(hand_t *hand, int32_t x, int32_t y);
/* 每个游戏帧调一次; play_w, play_h 是游戏区大小 */
void hand_update(hand_t *hand, const hand_raw_t *raw, int32_t play_w, int32_t play_h);
/* 游戏区坐标 (Q8) -> 摄像头小窗 (160x120) 里的点, 用来在小窗上标出手 */
void hand_to_window(int32_t x, int32_t y, int32_t play_w, int32_t play_h, int32_t *wx, int32_t *wy);

#endif
