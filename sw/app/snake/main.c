#include "lcd.h"
#include "shield_lcd.h"
#include "bsp.h"
#include "io.h"
#include "uart.h"
#include "key.h"
#include "app_board.h"          /* 本板的按键表、LED、read_settings: boards/<板>/ */

#include "snake.h"

#ifndef SNAKE_STEP_CYCLES
#if SIM_CYCLE_DIV > 1
/* 串口位速率不随延时缩放, 留够接收控制字符的时间。 */
#define SNAKE_STEP_CYCLES 1000000UL
#else
#define SNAKE_STEP_CYCLES (150UL * DELAY_CYCLES_PER_MS)
#endif
#endif

static snake_t snake;
static uint16_t cell_size;

static int uart_on = 1, wrap = 1;

/* 读设置 (各板实现不同, 见 boards/<板>/app_board.c), LED 显示当前状态 */
static void update_settings(void)
{
    read_settings(&uart_on, &wrap);
    io_write(LED_WRAP, wrap);
    io_write(LED_UART, uart_on);
}

/* 读按键和串口, 返回最新方向; 开局/暂停键 (或串口 p、空格) 按下时置 *start, 按了方向键置 *moved */
static snake_dir_t read_input(snake_dir_t dir, int *start, int *moved)
{
    snake_dir_t old = dir;
    char c;
    key_ticks(keys, KEY_N);
    update_settings();
    while (uart_getc(CONSOLE_UART, &c)) {
        if (!uart_on)
            continue;
        switch (c) {
        case 'k': case 'w': dir = SNAKE_UP; break;
        case 'j': case 's': dir = SNAKE_DOWN; break;
        case 'h': case 'a': dir = SNAKE_LEFT; break;
        case 'l': case 'd': dir = SNAKE_RIGHT; break;
        case 'p': case ' ': *start = 1; break;
        }
        *moved |= c != 'p' && c != ' ';
    }
    if (key_rose(&keys[K_START])) *start = 1;
    if (key_status(&keys[K_UP]))    dir = SNAKE_UP;
    if (key_status(&keys[K_DOWN]))  dir = SNAKE_DOWN;
    if (key_status(&keys[K_LEFT]))  dir = SNAKE_LEFT;
    if (key_status(&keys[K_RIGHT])) dir = SNAKE_RIGHT;
    *moved |= dir != old;
    return dir;
}

static void draw_cell(snake_cell_t cell, uint16_t color)
{
    if (cell_size == 8)
        lcd_fill_rect(cell.x * 8, cell.y * 8, 8, 8, color);
    else
        lcd_fill_rect(cell.x * 10, cell.y * 10, 10, 10, color);
}

int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    shield_lcd_init();
    cell_size = lcd_width() == 128 ? 8 : 10;
    snake_cols = 0;
    snake_rows = 0;
    snake_cells = 0;
    for (uint16_t w = lcd_width(); w >= cell_size; w -= cell_size)
        snake_cols++;
    for (uint16_t h = lcd_height(); h >= cell_size; h -= cell_size) {
        snake_rows++;
        snake_cells += snake_cols;
    }
    io_dir(LED_WRAP, IO_OUTPUT);
    io_dir(LED_UART, IO_OUTPUT);
    lcd_fill(LCD_BLACK);

    for (;;) {
        /* 等开局键或方向键; 按下时刻的周期数作随机种子 */
        snake_dir_t dir = SNAKE_RIGHT;
        int start = 0, moved = 0;
        while (!start && !moved)
            dir = read_input(dir, &start, &moved);
        snake_init(&snake, bsp_cycles());
        lcd_fill(LCD_BLACK);
        for (uint16_t i = 0; i < snake.length; i++)
            draw_cell(snake.body[i], LCD_GREEN);
        draw_cell(snake.food, LCD_RED);

        int paused = 0;
        while (!snake.game_over) {
            /* 等待期间一直读输入, 短按也不会漏掉 */
            uint32_t begin = bsp_cycles();
            while (bsp_cycles() - begin < SNAKE_STEP_CYCLES) {
                start = 0;
                dir = read_input(dir, &start, &moved);
                paused ^= start;
            }
            if (paused)
                continue;

            snake_change_t change;
            snake.wrap = wrap;
            snake_step(&snake, dir, &change);
            /* 新头可以占用刚腾出的尾格, 必须先擦尾。 */
            if (change.tail_removed)
                draw_cell(change.old_tail, LCD_BLACK);
            if (change.head_added)
                draw_cell(change.new_head, LCD_GREEN);
            if (change.food_added)
                draw_cell(change.new_food, LCD_RED);
            dir = snake.dir;
        }
        /* 撞死后停 1 秒再等下一局, 免得手还按着方向键就立刻重开 */
        delay_ms(1000);
    }
}
