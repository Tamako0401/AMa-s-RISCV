#include "fixed.h"

/* 四分之一圈的 sin, 64 等分加终点, Q14 */
static const int16_t sin_quarter[65] = {
    0,     402,   804,   1205,  1606,  2006,  2404,  2801,  3196,  3590,  3981,  4370,  4756,
    5139,  5520,  5897,  6270,  6639,  7005,  7366,  7723,  8076,  8423,  8765,  9102,  9434,
    9760,  10080, 10394, 10702, 11003, 11297, 11585, 11866, 12140, 12406, 12665, 12916, 13160,
    13395, 13623, 13842, 14053, 14256, 14449, 14635, 14811, 14978, 15137, 15286, 15426, 15557,
    15679, 15791, 15893, 15986, 16069, 16143, 16207, 16261, 16305, 16340, 16364, 16379, 16384,
};

/* atan(i / 32), i = 0..32, angle16 (8192 = 45 度) */
static const uint16_t atan_table[33] = {
    0,    326,  651,  975,  1297, 1617, 1933, 2246, 2555, 2860, 3159, 3453, 3742, 4025, 4302, 4572, 4836,
    5094, 5344, 5589, 5826, 6058, 6282, 6500, 6712, 6917, 7117, 7310, 7498, 7679, 7856, 8026, 8192,
};

int32_t fx_sin(uint32_t angle16)
{
    uint32_t i = (angle16 >> 8) & 255; /* 一圈 256 档 */
    uint32_t k = i & 63;
    switch (i >> 6) {
    case 0: return sin_quarter[k];
    case 1: return sin_quarter[64 - k];
    case 2: return -sin_quarter[k];
    default: return -sin_quarter[64 - k];
    }
}

int32_t fx_cos(uint32_t angle16)
{
    return fx_sin(angle16 + ANGLE_TURN / 4);
}

uint32_t fx_atan2(int32_t y, int32_t x)
{
    if (x == 0 && y == 0)
        return 0;
    int32_t ax = fx_abs(x), ay = fx_abs(y);
    /* 先算 0~45 度 (小边 / 大边), 再按象限翻回去 */
    int32_t small = ax < ay ? ax : ay, big = ax < ay ? ay : ax;
    uint32_t a = atan_table[(uint32_t)((small * 32 + big / 2) / big)];
    if (ay > ax)
        a = ANGLE_TURN / 4 - a;
    if (x < 0)
        a = ANGLE_TURN / 2 - a;
    if (y < 0)
        a = ANGLE_TURN - a;
    return a & (ANGLE_TURN - 1);
}

uint32_t fx_rand(uint32_t *state)
{
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return *state = x;
}
