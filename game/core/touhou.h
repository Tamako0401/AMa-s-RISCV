/* 东方式弹幕: 照 model/play.py 的玩法。boss 在上面左右移动, 轮流放三种弹幕, 越往后越密;
 * 自机自动射击, 打中 boss 得分。握拳移动, 张开一下放 bomb (清屏), 游戏结束后张开手 1 秒重开。
 * 只用整数和静态数组, 板上照用; 画面通过 gfx.h 描述。 */
#ifndef TOUHOU_H
#define TOUHOU_H

#include <stdint.h>
#include "hand.h"

#define PLAY_X 160 /* 游戏区在画面里的位置和大小; 两边各 160 是侧栏 */
#define PLAY_W 320
#define PLAY_H 360

#define TOUHOU_BULLETS 1024
#define TOUHOU_SHOTS 32
#define TOUHOU_SPARKS 64

typedef struct {
    int32_t x, y, vx, vy; /* 游戏区坐标, Q8; 速度 Q8 像素 / 帧 */
    uint8_t kind;         /* 哪种弹, 见 touhou.c */
    uint8_t angle;        /* 画的朝向, 一圈 256 */
} bullet_t;

/* 每帧做了多少事, 用来估计板上 CPU 够不够 */
typedef struct {
    uint32_t bullets_moved;
    uint32_t hit_tests; /* 做了精确判定 (算距离) 的次数 */
} touhou_work_t;

/* 每帧的输入: 手 (hand_t) 或电脑上的鼠标都转成这个 */
typedef struct {
    uint8_t has_pos;
    int32_t x, y;    /* 自机要去的位置, 游戏区坐标 Q8 */
    uint8_t bomb;    /* 这一帧放 bomb */
    uint8_t open;    /* 手在画面里而且张开 (游戏结束时按住 1 秒重开) */
    uint8_t restart; /* 直接重开 (电脑上按 R) */
} control_t;

typedef struct {
    uint32_t t; /* 这局第几帧 */
    int32_t px, py;
    uint8_t lives, bombs;
    uint16_t invincible; /* 剩几帧 */
    uint16_t bomb_t;     /* bomb 光环放了几帧, 0 表示没有 */
    int32_t bomb_x, bomb_y;
    uint32_t score;
    uint8_t level_bonus; /* 调试: 额外加的难度级别 (电脑上按 L), 用来造最密的画面 */
    uint8_t over;
    uint16_t hold; /* 游戏结束后张开手几帧 */
    uint32_t next_shot, next_fire;
    uint32_t spiral; /* 螺旋弹幕的当前角度, angle16 */
    uint32_t rng;
    uint32_t hits, bombs_used;
    bullet_t bullets[TOUHOU_BULLETS];
    uint16_t bullet_n;
    int32_t shots[TOUHOU_SHOTS][2];
    uint16_t shot_n;
    int32_t sparks[TOUHOU_SPARKS][3]; /* 打中 boss 的火花: x, y, 剩几帧 */
    uint16_t spark_n;
    touhou_work_t work;
} touhou_t;

void touhou_screen(void); /* 开机设一次: 底色、背景图块、小窗位置 */
void touhou_init(touhou_t *g, uint32_t seed);
void touhou_step(touhou_t *g, const control_t *in);
void touhou_draw(const touhou_t *g, const hand_t *hand);
int32_t touhou_level(const touhou_t *g);
/* 手 -> 控制 (握拳移动, 张开放 bomb) */
void touhou_control_from_hand(const hand_t *hand, control_t *in);

#endif
