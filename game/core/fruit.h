/* 水果忍者式: 水果从下面抛上来, 手在画面里就是刀, 划得够快才切得开。
 * 漏掉一个水果或切到炸弹扣一条命, 3 条命; 一刀切开 3 个以上有连击加分。游戏结束后张开手 1 秒重开 (同东方式)。
 * 整个画面都是游戏区 (640x360), 摄像头小窗在左上角、水果下面。
 * 只用整数和静态数组, 板上照用; 画面通过 gfx.h 描述。 */
#ifndef FRUIT_GAME_H
#define FRUIT_GAME_H

#include <stdint.h>
#include "hand.h"

#define FRUIT_W 640
#define FRUIT_H 360

#define FRUIT_MAX 32     /* 同时在飞的水果和炸弹 */
#define FRUIT_PIECES 64  /* 切开的半个 */
#define FRUIT_JUICE 256  /* 汁水点 */
#define FRUIT_TRAIL 10   /* 刀光: 记住最近几帧刀的位置 */

/* 水果、半个、汁水都用这个 */
typedef struct {
    int32_t x, y, vx, vy; /* Q8; 速度 Q8 像素 / 帧 */
    uint16_t angle;       /* 画的朝向, angle16 */
    int16_t spin;         /* 每帧转多少, angle16 */
    uint8_t kind;         /* 哪种水果, 见 fruit.c */
    uint8_t flip;         /* 半个: 另一半左右翻转 */
    uint8_t life;         /* 汁水: 还剩几帧 */
} fruit_obj_t;

/* 每帧的输入: 手或鼠标都转成这个 */
typedef struct {
    uint8_t has_pos;  /* 刀在画面里 (看得见手) */
    int32_t x, y;     /* 刀的位置, Q8 */
    uint8_t open;     /* 手张开 (游戏结束时按住 1 秒重开) */
    uint8_t restart;
} fruit_control_t;

typedef struct {
    uint32_t t;
    uint8_t lives;
    uint8_t level_bonus; /* 调试: 额外加的难度级别 */
    uint8_t over;
    uint8_t invincible;  /* 调试 (--bot): 不扣命 */
    uint16_t hold;       /* 游戏结束后张开手几帧 */
    uint32_t score, cut, missed, bombs_hit, best_combo;
    uint32_t next_wave, rng;
    int32_t trail[FRUIT_TRAIL][2]; /* [0] 是最新的, Q8 */
    uint8_t trail_n;
    uint8_t blade;       /* 刀在动 (够快, 切得开) */
    uint8_t combo;       /* 这一刀切开了几个 */
    uint16_t combo_show; /* 连击字样还显示几帧 */
    int32_t combo_x, combo_y;
    uint8_t combo_n;
    uint16_t flash;      /* 切到炸弹后闪白, 剩几帧 */
    fruit_obj_t fruits[FRUIT_MAX];
    uint16_t fruit_n;
    fruit_obj_t pieces[FRUIT_PIECES];
    uint16_t piece_n;
    fruit_obj_t juice[FRUIT_JUICE];
    uint16_t juice_n;
    uint32_t cut_tests;  /* 这一帧做了几次精确的切中判定 */
} fruit_t;

void fruit_screen(void); /* 开机设一次: 背景木板、小窗位置 */
void fruit_init(fruit_t *g, uint32_t seed);
void fruit_step(fruit_t *g, const fruit_control_t *in);
void fruit_draw(const fruit_t *g, const hand_t *hand);
int32_t fruit_level(const fruit_t *g);
/* 手 -> 控制: 看得见手就是刀 */
void fruit_control_from_hand(const hand_t *hand, fruit_control_t *in);

#endif
