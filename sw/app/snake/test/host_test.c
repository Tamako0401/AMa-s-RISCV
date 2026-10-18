#include <stdio.h>
#include "snake.h"

static int failures;

static void check(int passed, const char *name)
{
    printf("%s: %s\n", passed ? "PASS" : "FAIL", name);
    if (!passed)
        failures++;
}

static int same_cell(snake_cell_t a, snake_cell_t b)
{
    return a.x == b.x && a.y == b.y;
}

static snake_cell_t head_cell(const snake_t *snake)
{
    unsigned index = snake->tail + snake->length - 1;
    if (index >= SNAKE_CAPACITY)
        index -= SNAKE_CAPACITY;
    return snake->body[index];
}

static int food_is_free(const snake_t *snake)
{
    if (!snake->has_food || snake->food.x >= snake_cols ||
        snake->food.y >= snake_rows)
        return 0;
    unsigned index = snake->tail;
    for (unsigned i = 0; i < snake->length; i++) {
        if (same_cell(snake->food, snake->body[index]))
            return 0;
        index++;
        if (index == SNAKE_CAPACITY)
            index = 0;
    }
    return 1;
}

static void test_wall(void)
{
    snake_t snake;
    snake_change_t change;
    snake_init(&snake, 123);
    snake.food = (snake_cell_t){ 0, 0 };
    int passed = 1;
    for (int i = 0; i < 11; i++) {
        snake_step(&snake, SNAKE_RIGHT, &change);
        passed &= !snake.game_over && change.head_added && change.tail_removed;
        passed &= change.new_head.x == 13 + i && change.new_head.y == 16;
        passed &= change.old_tail.x == 10 + i && change.old_tail.y == 16;
        passed &= !change.food_added && snake.length == 3;
    }
    snake_step(&snake, SNAKE_RIGHT, &change);
    passed &= !snake.game_over && change.new_head.x == 0 && change.new_head.y == 16;
    snake_step(&snake, SNAKE_UP, &change);
    for (int i = 0; i < 16; i++)
        snake_step(&snake, SNAKE_UP, &change);
    passed &= !snake.game_over && change.new_head.x == 0 &&
              change.new_head.y == snake_rows - 1;
    check(passed, "straight movement and wrapping through walls");

    snake_init(&snake, 123);
    snake.food = (snake_cell_t){ 0, 0 };
    snake.wrap = 0;
    for (int i = 0; i < 11; i++)
        snake_step(&snake, SNAKE_RIGHT, &change);
    passed = !snake.game_over && head_cell(&snake).x == snake_cols - 1;
    snake_step(&snake, SNAKE_RIGHT, &change);
    check(passed && snake.game_over && !change.head_added && !change.tail_removed,
          "wrap off: hitting the wall ends the game");
    snake.game_over = 1;
    uint16_t tail = snake.tail;
    snake_step(&snake, SNAKE_LEFT, &change);
    check(snake.tail == tail && !change.head_added && !change.tail_removed &&
          !change.food_added, "step after game over changes no cells");
}

static void test_reverse(void)
{
    snake_t snake;
    snake_change_t change;
    snake_init(&snake, 123);
    snake.food = (snake_cell_t){ 0, 0 };
    snake_step(&snake, SNAKE_LEFT, &change);
    check(!snake.game_over && snake.dir == SNAKE_RIGHT &&
          change.head_added && change.new_head.x == 13 && change.new_head.y == 16,
          "reverse direction is ignored");
}

static void test_growth_and_collision(void)
{
    snake_t snake;
    snake_change_t change;
    snake_init(&snake, 123);
    snake_cell_t old_tail = snake.body[snake.tail];
    snake.food = (snake_cell_t){ 13, 16 };
    snake_step(&snake, SNAKE_RIGHT, &change);
    check(snake.length == 4 && snake.tail == 0 && change.head_added &&
          !change.tail_removed && change.food_added &&
          same_cell(snake.body[snake.tail], old_tail) &&
          same_cell(change.new_food, snake.food) && food_is_free(&snake),
          "eating grows snake, preserves tail and reports new food");
    snake.food = (snake_cell_t){ 13, 17 };
    snake_step(&snake, SNAKE_DOWN, &change);
    snake.food = (snake_cell_t){ 12, 17 };
    snake_step(&snake, SNAKE_LEFT, &change);
    int passed = snake.length == 6 && !snake.game_over;
    snake.food = (snake_cell_t){ 0, 0 };
    snake_cell_t old_head = head_cell(&snake);
    snake_step(&snake, SNAKE_UP, &change);
    check(passed && snake.game_over && snake.length == 6 &&
          same_cell(head_cell(&snake), old_head) && !change.head_added &&
          !change.tail_removed && !change.food_added,
          "right, down, left, up collides with body");
}

static void test_tail_entry(void)
{
    snake_t snake;
    snake_change_t change;
    snake_init(&snake, 123);
    snake.food = (snake_cell_t){ 13, 16 };
    snake_step(&snake, SNAKE_RIGHT, &change);
    snake.food = (snake_cell_t){ 0, 0 };
    snake_step(&snake, SNAKE_DOWN, &change);
    snake_step(&snake, SNAKE_LEFT, &change);
    snake_cell_t tail = snake.body[snake.tail];
    snake_step(&snake, SNAKE_UP, &change);
    check(!snake.game_over && snake.length == 4 && change.head_added &&
          change.tail_removed && same_cell(change.new_head, tail) &&
          same_cell(change.old_tail, tail), "moving into vacated tail is legal");
}

static void test_food(void)
{
    snake_t snake, other;
    snake_change_t change;
    int passed = 1;
    for (uint32_t seed = 0; seed < 1000; seed++) {
        snake_init(&snake, seed);
        snake_init(&other, seed);
        passed &= food_is_free(&snake) && same_cell(snake.food, other.food);
        passed &= snake.rng == other.rng;
    }
    check(passed, "1000 fixed seeds including zero: free and repeatable food");

    snake_init(&snake, 123);
    passed = 1;
    for (unsigned i = 0; i < 100; i++) {
        snake_cell_t next = head_cell(&snake);
        snake_dir_t dir = snake.dir;
        if ((dir == SNAKE_RIGHT && next.x == snake_cols - 1) ||
            (dir == SNAKE_LEFT && next.x == 0)) {
            dir = SNAKE_DOWN;
            next.y++;
        } else {
            if (dir == SNAKE_DOWN)
                dir = next.x == 0 ? SNAKE_RIGHT : SNAKE_LEFT;
            if (dir == SNAKE_RIGHT)
                next.x++;
            else
                next.x--;
        }
        snake.food = next;
        snake_step(&snake, dir, &change);
        passed &= !snake.game_over && snake.length == 4 + i;
        passed &= change.food_added && !change.tail_removed && food_is_free(&snake);
    }
    check(passed, "100 growth steps regenerate food outside growing body");
}

static void test_ring_wrap(void)
{
    static const snake_dir_t turns[] = {
        SNAKE_RIGHT, SNAKE_RIGHT, SNAKE_DOWN, SNAKE_DOWN,
        SNAKE_LEFT, SNAKE_LEFT, SNAKE_UP, SNAKE_UP
    };
    snake_t snake;
    snake_change_t change;
    snake_init(&snake, 123);
    snake.food = (snake_cell_t){ 0, 0 };
    int passed = 1;
    for (unsigned i = 0; i < 800; i++) {
        snake_step(&snake, turns[i & 7], &change);
        passed &= !snake.game_over && snake.length == 3 &&
                  change.head_added && change.tail_removed && !change.food_added;
    }
    check(passed && snake.tail == 32 && head_cell(&snake).x == 12 &&
          head_cell(&snake).y == 16, "800 steps wrap ring buffer");
}

static void test_full_board(void)
{
    snake_t snake;
    snake_change_t change;
    snake_init(&snake, 123);
    unsigned index = 0;
    /* 满图测试也要保持蛇身连通, 才能验证合法局面的结束规则。 */
    for (int x = 2; x < snake_cols; x++)
        snake.body[index++] = (snake_cell_t){ x, 0 };
    for (int y = 1; y < snake_rows; y++) {
        if (y & 1) {
            for (int x = snake_cols - 1; x >= 1; x--)
                snake.body[index++] = (snake_cell_t){ x, y };
        } else {
            for (int x = 1; x < snake_cols; x++)
                snake.body[index++] = (snake_cell_t){ x, y };
        }
    }
    for (int y = snake_rows - 1; y >= 0; y--)
        snake.body[index++] = (snake_cell_t){ 0, y };
    snake.length = index;
    snake.dir = SNAKE_UP;
    snake.food = (snake_cell_t){ 1, 0 };
    snake_step(&snake, SNAKE_RIGHT, &change);
    check(snake.game_over && snake.length == SNAKE_CAPACITY &&
          !snake.has_food && change.head_added && !change.tail_removed &&
          !change.food_added && same_cell(change.new_head, snake.food),
          "full board finishes without trying to place food");
}

int main(void)
{
    test_wall();
    test_reverse();
    test_growth_and_collision();
    test_tail_entry();
    test_food();
    test_ring_wrap();
    test_full_board();
    printf("%s: %d failures\n", failures ? "FAIL" : "PASS", failures);
    return failures != 0;
}
