#include "snake.h"

uint16_t snake_cols = 24, snake_rows = 32, snake_cells = SNAKE_CAPACITY;

static uint16_t body_index(uint16_t index)
{
    if (index >= SNAKE_CAPACITY)
        index -= SNAKE_CAPACITY;
    return index;
}

static uint32_t random_next(snake_t *snake)
{
    uint32_t x = snake->rng;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    snake->rng = x;
    return x;
}

static int body_contains(const snake_t *snake, snake_cell_t cell,
                         uint16_t start, uint16_t count)
{
    for (uint16_t i = 0; i < count; i++) {
        snake_cell_t part = snake->body[body_index(start + i)];
        if (part.x == cell.x && part.y == cell.y)
            return 1;
    }
    return 0;
}

static void place_food(snake_t *snake)
{
    snake_cell_t food;
    do {
        do {
            food.x = random_next(snake) & 31;
        } while (food.x >= snake_cols);
        do {
            food.y = random_next(snake) & 31;
        } while (food.y >= snake_rows);
    } while (body_contains(snake, food, snake->tail, snake->length));
    snake->food = food;
    snake->has_food = 1;
}

void snake_init(snake_t *snake, uint32_t seed)
{
    snake->tail = 0;
    snake->length = 3;
    snake->dir = SNAKE_RIGHT;
    snake->game_over = 0;
    snake->wrap = 1;
    /* xorshift 的零状态不会变化, 零种子也要能放出食物。 */
    snake->rng = seed ? seed : 1;
    for (uint16_t i = 0; i < snake->length; i++) {
        snake->body[i].x = (snake_cols >> 1) - 2 + i;
        snake->body[i].y = snake_rows >> 1;
    }
    place_food(snake);
}

void snake_step(snake_t *snake, snake_dir_t dir, snake_change_t *change)
{
    change->head_added = 0;
    change->tail_removed = 0;
    change->food_added = 0;
    if (snake->game_over)
        return;

    if (dir != (snake_dir_t)(snake->dir ^ 1))
        snake->dir = dir;

    snake_cell_t head = snake->body[body_index(snake->tail + snake->length - 1)];
    int x = head.x;
    int y = head.y;
    switch (snake->dir) {
    case SNAKE_UP:    y--; break;
    case SNAKE_DOWN:  y++; break;
    case SNAKE_LEFT:  x--; break;
    case SNAKE_RIGHT: x++; break;
    }
    if (!snake->wrap && (x < 0 || x >= snake_cols || y < 0 || y >= snake_rows)) {
        snake->game_over = 1;
        return;
    }
    if (x < 0) x = snake_cols - 1;
    if (x >= snake_cols) x = 0;
    if (y < 0) y = snake_rows - 1;
    if (y >= snake_rows) y = 0;

    snake_cell_t next = { x, y };
    int eating = x == snake->food.x && y == snake->food.y;
    /* 不生长时尾格会同时腾空, 可以成为新蛇头。 */
    uint16_t start = body_index(snake->tail + !eating);
    if (body_contains(snake, next, start, snake->length - !eating)) {
        snake->game_over = 1;
        return;
    }

    change->old_tail = snake->body[snake->tail];
    snake->body[body_index(snake->tail + snake->length)] = next;
    change->new_head = next;
    change->head_added = 1;
    if (!eating) {
        snake->tail = body_index(snake->tail + 1);
        change->tail_removed = 1;
        return;
    }

    snake->length++;
    /* 满图时已无空格, 直接结束而不再重抽食物。 */
    if (snake->length == snake_cells) {
        snake->has_food = 0;
        snake->game_over = 1;
        return;
    }
    place_food(snake);
    change->new_food = snake->food;
    change->food_added = 1;
}
