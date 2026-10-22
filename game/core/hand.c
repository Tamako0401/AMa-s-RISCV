#include "hand.h"
#include "fixed.h"

#define SWITCH 3     /* 连续几次结果都是另一种手势才切换 */
#define LOST_RESET 18 /* 丢手超过这么多帧 (0.3 秒), 重新出现时不从旧位置滑过去 */
#define FPS 60

/* One Euro 滤波 (Casiez 2012) 的参数, 意义见 play.py 的 OneEuro。
 * play.py 的画面是 320x240 (有效区高映射到 240), 这里映射到 360, 速度大 1.5 倍, beta 相应除 1.5 */
#define MIN_CUTOFF Q8(1.0)    /* Hz, Q8 */
#define SPEED_CUTOFF Q8(1.0)
#define BETA 874              /* Q16, 0.02 / 1.5 */

void hand_init(hand_t *hand, int32_t x, int32_t y)
{
    *hand = (hand_t){0};
    hand->x = x;
    hand->y = y;
}

/* 截止频率 cutoff (Q8 Hz) 的一阶低通, 隔 frames 帧更新一次时新值占的比例 (Q16):
 * a = r / (r + 1), r = 2 pi * cutoff * dt */
static int32_t alpha(int32_t cutoff, uint32_t frames)
{
    int64_t r = (int64_t)cutoff * frames * 6863 >> 8; /* 6863 = 2 pi / 60 * 65536 */
    return (int32_t)((r << 16) / (r + 65536));
}

static int32_t blend(int32_t old, int32_t now, int32_t a)
{
    return old + (int32_t)((int64_t)(now - old) * a >> 16);
}

static void smooth(hand_t *hand, int32_t x, int32_t y)
{
    uint32_t frames = hand->since < 8 ? hand->since : 8;
    if (!hand->filtering) {
        hand->fx = x;
        hand->fy = y;
        hand->sx = hand->sy = 0;
        hand->filtering = 1;
        return;
    }
    /* 速度也平滑一下, 不然噪声会被当成快速移动 */
    int32_t a = alpha(SPEED_CUTOFF, frames);
    hand->sx = blend(hand->sx, (x - hand->fx) * FPS / (int32_t)frames, a);
    hand->sy = blend(hand->sy, (y - hand->fy) * FPS / (int32_t)frames, a);
    /* 速度大小: 不开方, 用 大 + 小 / 2 近似 (误差 12% 以内) */
    int32_t ax = fx_abs(hand->sx), ay = fx_abs(hand->sy);
    int32_t speed = ax > ay ? ax + ay / 2 : ay + ax / 2;
    int32_t cutoff = MIN_CUTOFF + (int32_t)((int64_t)BETA * speed >> 16);
    a = alpha(cutoff, frames);
    hand->fx = blend(hand->fx, x, a);
    hand->fy = blend(hand->fy, y, a);
}

static int32_t clamp(int32_t v, int32_t lo, int32_t hi)
{
    return v < lo ? lo : v > hi ? hi : v;
}

void hand_update(hand_t *hand, const hand_raw_t *raw, int32_t play_w, int32_t play_h)
{
    hand->opened = 0;
    hand->since++;
    if (raw->seq == hand->seq)
        return;
    hand->seq = raw->seq;

    hand->found = raw->found != 0;
    if (!raw->found) {
        hand->lost += hand->since;
        if (hand->lost > LOST_RESET)
            hand->filtering = 0;
        hand->since = 0;
        return;
    }
    hand->lost = 0;

    /* 有效区映射到游戏区 */
    int32_t x = ((raw->x - (HAND_CAM_W - HAND_ACTIVE_W) / 2) * play_w << 8) / HAND_ACTIVE_W;
    int32_t y = ((raw->y - (HAND_CAM_H - HAND_ACTIVE_H) / 2) * play_h << 8) / HAND_ACTIVE_H;
    smooth(hand, x, y);
    hand->since = 0;
    hand->x = clamp(hand->fx, 0, Q8(play_w) - 1);
    hand->y = clamp(hand->fy, 0, Q8(play_h) - 1);
    hand->valid = 1;

    /* 防抖: 连续 SWITCH 次都是另一种手势才切换; 说不清的不算数, 也不打断 */
    if (raw->fist < 0)
        return;
    if ((raw->fist != 0) != hand->fist) {
        if (++hand->streak >= SWITCH) {
            hand->fist = !hand->fist;
            hand->streak = 0;
            hand->opened = !hand->fist;
        }
    } else {
        hand->streak = 0;
    }
}
