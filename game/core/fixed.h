/* 定点数学: 板上 CPU 没有浮点, 游戏里只用整数。
 * 坐标、速度用 Q8 (低 8 位是小数, 256 = 1 像素); 角度一圈 65536 (angle16), 查表时只用高 8 位。 */
#ifndef FIXED_H
#define FIXED_H

#include <stdint.h>

#define Q8(n) ((int32_t)((n) * 256))
#define ANGLE_TURN 65536 /* 一圈 */

/* sin / cos, 结果 Q14 (16384 = 1.0) */
int32_t fx_sin(uint32_t angle16);
int32_t fx_cos(uint32_t angle16);

/* 从原点看 (x, y) 的方向, angle16; x 向右、y 向下, 0 是正右方 */
uint32_t fx_atan2(int32_t y, int32_t x);

/* 伪随机数 (xorshift32), 板上和电脑上序列一样 */
uint32_t fx_rand(uint32_t *state);

static inline int32_t fx_abs(int32_t x)
{
    return x < 0 ? -x : x;
}

#endif
