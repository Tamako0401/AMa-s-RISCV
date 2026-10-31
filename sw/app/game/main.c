/* game: 板上玩两个手势游戏 (game/core/, 和电脑版同一份), 画面走新显示 (位流要 DISPLAY_NEW=1, 见 app.toml)。
 * 输入从串口来 (见 game/board/pad.h): ama monitor 打字, 或 ama monitor --pad (真正的按住 / 松开和鼠标)。
 * 输入方式 (按键 / 指点) 同一时间只有一种管用, 在暂停菜单里切换 (MENU = m / q / Esc, 见 game/board/menu.h)。
 * 开机是标题画面: 上下选游戏, A (j / 空格 / 回车) 开始; 游戏里 r 重开, 结束后 A (指点方式: 左键) 重开。
 *   东方式: 按键: 方向键移动 (大写 / Shift 慢速), A 放 bomb; 指点: 鼠标 / 手就是自机位置, 左键 / 张开手 bomb。
 *   水果忍者式: 按键: 方向键移动刀尖, A 沿最近移动的方向砍一刀 (冲出一段, 够快才切得开); 指点: 鼠标 / 手直接划。
 * 串口每局结束打印成绩, 每 5 秒打印一次 CPU 每帧用了多少拍和显示最忙一行的拍数。 */
#include "assets.h"
#include "board_hdmi.h"
#include "bsp.h"
#include "fixed.h"
#include "fruit.h"
#include "gfx.h"
#include "gfx_hw.h"
#include "menu.h"
#include "pad.h"
#include "touhou.h"
#include "uart.h"

#define FPS 60
#define TOUHOU_SPEED 768 /* Q8 像素 / 帧: 3 点 (180 点 / 秒) */
#define TOUHOU_SLOW 320
#define CURSOR_SPEED 1536 /* 水果: 刀尖平时 6 点 / 帧 */
#define SLASH_STEP 8192   /* 一刀每帧冲 32 点 (刀要每帧 5 点以上才切得开) */
#define SLASH_FRAMES 5

enum { TITLE, TOUHOU, FRUIT };

static union { /* 两个游戏不会同时玩, 共用内存 */
    touhou_t touhou;
    fruit_t fruit;
} game;
static pad_t pad;
static hand_t hand; /* 还没接视觉: 一直是 "没有手" */
static uint8_t input_mode = INPUT_KEYS;
static menu_t menu;
static uint32_t seed = 1;

static void put_num(uint32_t n)
{
    char buf[11];
    int i = 10;
    buf[i] = 0;
    do {
        buf[--i] = (char)('0' + n % 10);
        n /= 10;
    } while (n);
    uart_puts(CONSOLE_UART, buf + i);
}

/* 方向键 -> (-1/0/1, -1/0/1) */
static int32_t dir_x(uint32_t keys)
{
    return (keys & PAD_RIGHT ? 1 : 0) - (keys & PAD_LEFT ? 1 : 0);
}

static int32_t dir_y(uint32_t keys)
{
    return (keys & PAD_DOWN ? 1 : 0) - (keys & PAD_UP ? 1 : 0);
}

static int32_t clamp(int32_t v, int32_t lo, int32_t hi)
{
    return v < lo ? lo : v > hi ? hi : v;
}

/* ---- 标题 ---- */

static int32_t choice;

static void title_screen(void)
{
    gfx_backdrop(0x0841);
    gfx_clip(0, 0); /* 不显示背景 */
    gfx_text_clear();
    gfx_text(64, 10, GFX_WHITE, "AMa-s-RISCV  GAME");
    gfx_text(56, 30, GFX_GRAY, "up/down: choose   j/space: start");
    gfx_text(56, 31, GFX_GRAY, "m: menu (change input)   r: restart");
}

static void title_frame(uint32_t t)
{
    static const char *const names[] = {"  bullet hell (touhou)", "  fruit slicer"};
    if (pad.pressed & (PAD_UP | PAD_DOWN))
        choice ^= 1;
    for (int32_t i = 0; i < 2; i++) {
        gfx_text(60, 18 + 3 * i, i == choice ? GFX_YELLOW : GFX_LIGHT_GRAY, names[i]);
        gfx_text(60, 18 + 3 * i, GFX_YELLOW, i == choice ? ">" : " ");
    }
    gfx_text(60, 26, GFX_GRAY, input_mode == INPUT_KEYS ? "  input: keys " : "  input: point");
    gfx_begin();
    /* 选中那一项旁边转几个光点 */
    for (uint32_t i = 0; i < 6; i++) {
        uint32_t a = t * 600 + i * (ANGLE_TURN / 6);
        /* 文字第 c 列第 r 行在画面上是 (4c, 8r): 文字层是 1280x720, 画面 640x360 */
        gfx_sprite_t *s =
            gfx_sprite(236 + 16 * fx_cos(a) / 16384, 148 + 24 * choice + 8 * fx_sin(a) / 16384, IMG_SPARK);
        s->flags = GFX_ADD;
    }
}

/* ---- 东方式 ---- */

static void touhou_frame(void)
{
    touhou_t *g = &game.touhou;
    control_t c = {.has_pos = 1, .x = g->px, .y = g->py};
    uint32_t a = PAD_A;              /* 这种输入方式下的 A */
    if (input_mode == INPUT_POINT) { /* 鼠标在 pad.py 窗口里就听鼠标, 不然听手 */
        touhou_control_from_hand(&hand, &c);
        if (pad.mouse) {
            c.has_pos = 1;
            c.x = Q8(clamp(pad.mx - PLAY_X, 0, PLAY_W - 1));
            c.y = Q8(clamp(pad.my, 0, PLAY_H - 1));
        }
        a = PAD_CLICK;
    } else {
        int32_t v = pad.held & PAD_SLOW ? TOUHOU_SLOW : TOUHOU_SPEED;
        c.x = clamp(c.x + dir_x(pad.held) * v, 0, Q8(PLAY_W - 1));
        c.y = clamp(c.y + dir_y(pad.held) * v, 0, Q8(PLAY_H - 1));
    }
    c.bomb |= (pad.pressed & a) != 0;
    c.restart = (pad.pressed & PAD_RESTART) || (g->over && (pad.pressed & a));
    touhou_step(g, &c);
    touhou_draw(g, &hand);
}

static void touhou_report(void)
{
    touhou_t *g = &game.touhou;
    uart_puts(CONSOLE_UART, "touhou: ");
    put_num(g->t / FPS);
    uart_puts(CONSOLE_UART, " s, score ");
    put_num(g->score);
    uart_puts(CONSOLE_UART, ", bombs ");
    put_num(g->bombs_used);
    uart_puts(CONSOLE_UART, "\r\n");
}

/* ---- 水果忍者式 ---- */

static int32_t cx, cy, last_dx, last_dy = -1;
static uint32_t slash; /* 这一刀还冲几帧 */

static void fruit_frame(void)
{
    fruit_t *g = &game.fruit;
    fruit_control_t c = {.has_pos = 1};
    uint32_t a = PAD_A;
    if (input_mode == INPUT_POINT) { /* 鼠标在 pad.py 窗口里就听鼠标, 不然听手 */
        fruit_control_from_hand(&hand, &c);
        if (pad.mouse) {
            c.has_pos = 1;
            c.x = Q8(pad.mx);
            c.y = Q8(pad.my);
        }
        a = PAD_CLICK;
    } else {
        int32_t dx = dir_x(pad.held), dy = dir_y(pad.held);
        if (dx || dy) {
            last_dx = dx;
            last_dy = dy;
        }
        if (pad.pressed & PAD_A && !slash)
            slash = SLASH_FRAMES;
        int32_t v = slash ? SLASH_STEP : CURSOR_SPEED;
        if (slash) {
            slash--;
            dx = last_dx;
            dy = last_dy;
        }
        cx = clamp(cx + dx * v, 0, Q8(FRUIT_W - 1));
        cy = clamp(cy + dy * v, 0, Q8(FRUIT_H - 1));
        c.x = cx;
        c.y = cy;
    }
    c.restart = (pad.pressed & PAD_RESTART) || (g->over && (pad.pressed & a));
    fruit_step(g, &c);
    fruit_draw(g, &hand);
    if (input_mode == INPUT_KEYS) { /* 刀尖: 按键玩时要看得见在哪 */
        gfx_sprite_t *s = gfx_sprite(cx >> 8, cy >> 8, IMG_SPARK);
        s->flags = GFX_ADD;
    }
}

static void fruit_report(void)
{
    fruit_t *g = &game.fruit;
    uart_puts(CONSOLE_UART, "fruit: score ");
    put_num(g->score);
    uart_puts(CONSOLE_UART, ", cut ");
    put_num(g->cut);
    uart_puts(CONSOLE_UART, ", missed ");
    put_num(g->missed);
    uart_puts(CONSOLE_UART, "\r\n");
}

/* ---- 主循环 ---- */

static void enter(int32_t which)
{
    if (which == TOUHOU) {
        touhou_screen();
        touhou_init(&game.touhou, seed);
        game.touhou.px = Q8(PLAY_W / 2);
        game.touhou.py = Q8(PLAY_H * 4 / 5);
    } else if (which == FRUIT) {
        fruit_screen();
        fruit_init(&game.fruit, seed);
        cx = Q8(FRUIT_W / 2);
        cy = Q8(FRUIT_H / 2);
        slash = 0;
    } else
        title_screen();
}

int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    int hdmi = board_hdmi_init();
    uart_puts(CONSOLE_UART, hdmi & 1 ? "game: HDMI out no answer\r\n" : "game: HDMI out ok\r\n");
    gfx_hw_init();
    hand_init(&hand, 0, 0);

    int32_t state = TITLE, was_over = 0, paused = 0;
    uint32_t t = 0, work = 0, work_max = 0, report_at = 5 * FPS;
    enter(TITLE);
    for (;;) {
        uint32_t start = bsp_cycles();
        pad_poll(&pad);
        seed = seed * 1664525 + 1013904223 + pad.held; /* 开局的随机数和按键时机有关 */
        int32_t over = was_over;
        if (paused) { /* 暂停: 精灵表不动 (不调 gfx_begin), 画面变暗, 上面写菜单 */
            menu_info_t info = {.hand = &hand, .cpu = work};
            int r = menu_frame(&menu, &pad, &input_mode, &info);
            gfx_fade(0x0000, 10);
            if (r != MENU_STAY) {
                menu_close();
                paused = 0;
                if (r == MENU_TITLE)
                    state = TITLE;
                if (state == TITLE) { /* 菜单盖掉了标题的字, 重写 */
                    enter(TITLE);
                    gfx_begin();
                }
            }
        } else if (pad.pressed & PAD_MENU) {
            paused = 1;
            menu_open(&menu, state != TITLE);
            gfx_fade(0x0000, 10);
        } else if (state == TITLE) {
            title_frame(t);
            if (pad.pressed & (PAD_A | PAD_CLICK)) {
                state = choice ? FRUIT : TOUHOU;
                enter(state);
            }
            over = 0;
        } else if (state == TOUHOU) {
            touhou_frame();
            over = game.touhou.over;
            if (over && !was_over)
                touhou_report();
        } else {
            fruit_frame();
            over = game.fruit.over;
            if (over && !was_over)
                fruit_report();
        }
        was_over = over;
        work = bsp_cycles() - start;
        if (work > work_max)
            work_max = work;
        gfx_hw_present();
        if (++t == report_at) { /* 每 5 秒: CPU 最忙一帧用了多少拍 (一帧 833k 拍), 显示最忙一行 (共 2222 拍) */
            report_at += 5 * FPS;
            uart_puts(CONSOLE_UART, "cpu max ");
            put_num(work_max);
            uart_puts(CONSOLE_UART, " cycles/frame, line max ");
            put_num(gfx_hw_line_max());
            uart_puts(CONSOLE_UART, ", overrun ");
            put_num(gfx_hw_overrun());
            uart_puts(CONSOLE_UART, "\r\n");
            work_max = 0;
        }
    }
}
