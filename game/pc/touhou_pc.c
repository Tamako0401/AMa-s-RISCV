/* 东方式弹幕的电脑版: 把 core/touhou.c 接到电脑后端 (app.c)。
 * 鼠标: 自机跟着鼠标, 左键 bomb。--bot: 自机在下半场绕椭圆, 一直无敌。 */
#include <stdio.h>
#include "app.h"
#include "fixed.h"
#include "gfx.h"
#include "touhou.h"

#define FPS 60

static touhou_t game;

static void start(int32_t level)
{
    touhou_screen();
    touhou_init(&game, 1);
    game.level_bonus = (uint8_t)level;
}

static void frame(const hand_t *hand, const app_input_t *in, int use_hand, int bot)
{
    control_t c;
    if (use_hand)
        touhou_control_from_hand(hand, &c);
    else
        c = (control_t){.has_pos = 1, .x = in->x, .y = in->y, .bomb = in->click};
    if (bot) {
        c = (control_t){.has_pos = 1};
        c.x = Q8(PLAY_W / 2) + 120 * fx_cos(in->frame * 200) / 64;
        c.y = Q8(PLAY_H * 3 / 4) + 50 * fx_sin(in->frame * 330) / 64;
        game.invincible = 2; /* step 里先减 1 再判定 */
    }
    c.restart = in->restart;
    touhou_step(&game, &c);
    touhou_draw(&game, hand);
}

static void level(int32_t delta)
{
    game.level_bonus = delta ? game.level_bonus + 1 : 0;
}

static int over(void)
{
    return game.over;
}

static void report(void)
{
    printf("坚持 %u 秒, 得分 %u, 被击中 %u 次, 用 bomb %u 个", game.t / FPS, game.score, game.hits, game.bombs_used);
}

static void debug(void)
{
    gfx_text(4, 40, GFX_GRAY, "MOVED");
    gfx_number(14, 40, GFX_WHITE, game.work.bullets_moved, 5);
    gfx_text(4, 41, GFX_GRAY, "HIT TEST");
    gfx_number(14, 41, GFX_WHITE, game.work.hit_tests, 5);
}

int main(int argc, char **argv)
{
    static const app_game_t touhou = {"touhou", PLAY_X, PLAY_W, PLAY_H, start, frame, level, over, report, debug};
    return app_main(&touhou, argc, argv);
}
