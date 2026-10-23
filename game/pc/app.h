/* 电脑后端的公共部分: 窗口、定 60 帧/秒的主循环、鼠标键盘、UDP 收手的结果、统计和存帧。
 * 每个游戏写一个很薄的 pc/<游戏>_pc.c: 填好 app_game_t, main 里调 app_main。 */
#ifndef APP_H
#define APP_H

#include <stdint.h>
#include "hand.h"

/* 电脑上的输入 (没开手的时候用鼠标) */
typedef struct {
    int32_t x, y;     /* 鼠标在游戏区里的位置, Q8 */
    uint8_t click;    /* 这一帧按下了左键 */
    uint8_t restart;  /* 这一帧按了 R */
    uint32_t frame;   /* 第几帧 (从 0 起), --bot 用来算路线 */
} app_input_t;

typedef struct {
    const char *name;
    int32_t play_x, play_w, play_h; /* 游戏区在画面里的位置和大小: 鼠标、手都映射到这里 */
    void (*start)(int32_t level);   /* 开机: 设画面, 开第一局; level 同 --level */
    /* 一帧: 手或鼠标 -> 游戏的输入, 走一步, 画。bot 时不看输入, 自己动 (跑统计用) */
    void (*frame)(const hand_t *hand, const app_input_t *in, int use_hand, int bot);
    void (*level)(int32_t delta); /* L 键 delta = 1 加一级, K 键 delta = 0 恢复 */
    int (*over)(void);
    void (*report)(void);         /* 打印这局成绩 (不换行) */
    void (*debug)(void);          /* 游戏自己的调试信息 (左下, 第 40 行起), 可以为 NULL */
} app_game_t;

int app_main(const app_game_t *game, int argc, char **argv);

#endif
