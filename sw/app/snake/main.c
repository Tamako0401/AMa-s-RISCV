#include "lcd.h"
#include "bsp.h"
#include "uart.h"

#include "snake.h"

#ifndef SNAKE_STEP_CYCLES
#define SNAKE_STEP_CYCLES (150UL * DELAY_CYCLES_PER_MS)
#endif

#ifdef BOARD_EGO1
#define KEY_UP PIN_S4
#define KEY_LEFT PIN_S3
#define KEY_START PIN_S2
#define KEY_RIGHT PIN_S0
#define KEY_DOWN PIN_S1
#define LED_WRAP PIN_LD2_0          /* 挨着拨码开关 SW0 */
#define LED_UART PIN_LD2_1
#else
#define KEY_UP PIN_KEY7
#define KEY_LEFT PIN_KEY5
#define KEY_START PIN_KEY2
#define KEY_RIGHT PIN_KEY8
#define KEY_DOWN PIN_KEY6
#define KEY_UART PIN_KEY3
#define KEY_WRAP PIN_KEY4
#define LED_UART PIN_LED3           /* 灯号和按键号一致 */
#define LED_WRAP PIN_LED4
#endif

static snake_t snake;
static uint16_t cell_size;

static int uart_on = 1, wrap = 1;

/* 按下那一刻返回 1, 按住不重复 */
static int key_edge(uint32_t pin, int *last)
{
    int now = io_read(pin);
    int hit = now && !*last;
    *last = now;
    return hit;
}

/* 穿墙、串口控制两个开关: EGO1 用拨码开关 (拨上 = 开), 盘古的按键每按一下切换; LED 显示当前状态 */
static void read_settings(void)
{
#ifdef BOARD_EGO1
    wrap = io_read(PIN_SW0);
    uart_on = io_read(PIN_SW1);
#else
    static int uart_last, wrap_last;
    if (key_edge(KEY_UART, &uart_last)) uart_on = !uart_on;
    if (key_edge(KEY_WRAP, &wrap_last)) wrap = !wrap;
#endif
    io_write(LED_WRAP, wrap);
    io_write(LED_UART, uart_on);
}

/* 读按键和串口, 返回最新方向; 开局/暂停键 (或串口 p、空格) 按下时置 *start, 按了方向键置 *moved */
static snake_dir_t read_input(snake_dir_t dir, int *start, int *moved)
{
    static int start_last;
    snake_dir_t old = dir;
    char c;
    read_settings();
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
    if (key_edge(KEY_START, &start_last)) *start = 1;
    if (io_read(KEY_UP))    dir = SNAKE_UP;
    if (io_read(KEY_DOWN))  dir = SNAKE_DOWN;
    if (io_read(KEY_LEFT))  dir = SNAKE_LEFT;
    if (io_read(KEY_RIGHT)) dir = SNAKE_RIGHT;
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
#ifdef BOARD_EGO1
    lcd_init_st7735(&(lcd_pins_t){ .sck = PIN_J5_1, .mosi = PIN_J5_2, .rst = PIN_J5_3,
                                   .dc = PIN_J5_4, .bl = PIN_J5_5, .cs = PIN_J5_6 });
#else
    lcd_init_st7789(&(lcd_pins_t){ .sck = PIN_J8_27, .mosi = PIN_J8_28, .cs = PIN_J8_23,
                                   .dc = PIN_J8_26, .rst = PIN_J8_25, .bl = PIN_J8_24 });
#endif
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
