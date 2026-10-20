#ifndef SNAKE_H
#define SNAKE_H

#include <stdint.h>

/* 最大屏幕 240x320, 每格 10 像素; 小屏按运行时尺寸取格子数。 */
#define SNAKE_CAPACITY (24 * 32)
extern uint16_t snake_cols, snake_rows, snake_cells;

typedef struct {
    uint8_t x, y;
} snake_cell_t;

typedef enum { SNAKE_UP, SNAKE_DOWN, SNAKE_LEFT, SNAKE_RIGHT } snake_dir_t;

typedef struct {
    snake_cell_t body[SNAKE_CAPACITY];
    uint16_t tail;
    uint16_t length;
    snake_dir_t dir;
    snake_cell_t food;
    uint32_t rng;
    uint8_t has_food;
    uint8_t game_over;
    uint8_t wrap; /* 1: 穿墙从对边出来; 0: 撞墙结束 */
} snake_t;

/* 尾格可能同时成为新头, 上层需先擦尾再画头。 */
typedef struct {
    uint8_t head_added;
    uint8_t tail_removed;
    uint8_t food_added;
    snake_cell_t new_head;
    snake_cell_t old_tail;
    snake_cell_t new_food;
} snake_change_t;

void snake_init(snake_t *snake, uint32_t seed);
void snake_step(snake_t *snake, snake_dir_t dir, snake_change_t *change);

#endif
