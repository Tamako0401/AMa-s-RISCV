/* 按键: 定时采样 + 消抖. 读到 1 = 按下 (低有效的板子已在板级顶层取反) */
#ifndef KEY_H
#define KEY_H

#include <stdint.h>

#define KEY_SAMPLE_MS 5  /* 采样间隔 */
#define DEBOUNCE_TICKS 4 /* 连续这么多次读到新电平才算变了: 4 x 5ms = 20ms */

typedef struct {
    uint32_t pin;
    uint8_t now : 1, last : 1, debounce_cnt : 4;
} key_t;

/* 主循环每轮调一次. 只用一个按键数组: 采样时刻是全局的 */
void key_ticks(key_t *keys, int key_num);

/* 以下只读 key_ticks 存下的状态, 同一轮里问几次结果都一样 */
static inline int key_rose(const key_t *k)
{
    return k->now && !k->last;
} /* 按下那一轮 */
static inline int key_fell(const key_t *k)
{
    return !k->now && k->last;
} /* 松开那一轮 */
static inline int key_status(const key_t *k)
{
    return k->now;
} /* 正按着 */

#endif
