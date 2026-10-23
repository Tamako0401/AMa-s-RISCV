/* 水果忍者式的电脑版: 把 core/fruit.c 接到电脑后端 (app.c)。
 * 鼠标: 刀跟着鼠标, 划得够快就切。--bot: 刀自己绕 8 字快速来回划, 不扣命。 */
#include <stdio.h>
#include "app.h"
#include "fixed.h"
#include "fruit.h"
#include "gfx.h"

#define FPS 60

static fruit_t game;

static void start(int32_t level)
{
    fruit_screen();
    fruit_init(&game, 1);
    game.level_bonus = (uint8_t)level;
}

static void frame(const hand_t *hand, const app_input_t *in, int use_hand, int bot)
{
    fruit_control_t c;
    if (use_hand)
        fruit_control_from_hand(hand, &c);
    else
        c = (fruit_control_t){.has_pos = 1, .x = in->x, .y = in->y};
    if (bot) { /* 在最高的那个水果附近画小圈 (约 2 圈 / 秒, 刀速约 12 点 / 帧), 不扣命 */
        static int32_t cx = Q8(FRUIT_W / 2), cy = Q8(FRUIT_H / 2);
        int32_t tx = Q8(FRUIT_W / 2), ty = Q8(FRUIT_H / 2), top = Q8(FRUIT_H - 40);
        for (uint16_t i = 0; i < game.fruit_n; i++)
            if (game.fruits[i].y < top && game.fruits[i].kind != 3) { /* 3 = 炸弹, 躲开 */
                top = game.fruits[i].y;
                tx = game.fruits[i].x;
                ty = game.fruits[i].y;
            }
        cx += (tx - cx) / 8; /* 手不会瞬移: 慢慢跟过去 */
        cy += (ty - cy) / 8;
        c = (fruit_control_t){.has_pos = 1};
        c.x = cx + 50 * fx_cos(in->frame * 2200) / 64;
        c.y = cy + 50 * fx_sin(in->frame * 2200) / 64;
        game.invincible = 1;
    }
    c.restart = in->restart;
    fruit_step(&game, &c);
    fruit_draw(&game, hand);
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
    printf("坚持 %u 秒, 得分 %u, 切开 %u 个, 漏掉 %u 个, 切到炸弹 %u 次, 最大连击 %u", game.t / FPS, game.score, game.cut,
           game.missed, game.bombs_hit, game.best_combo);
}

static void debug(void)
{
    gfx_text(4, 40, GFX_GRAY, "OBJECTS");
    gfx_number(14, 40, GFX_WHITE, game.fruit_n + game.piece_n + game.juice_n, 5);
    gfx_text(4, 41, GFX_GRAY, "CUT TEST");
    gfx_number(14, 41, GFX_WHITE, game.cut_tests, 5);
}

int main(int argc, char **argv)
{
    static const app_game_t fruit = {"fruit", 0, FRUIT_W, FRUIT_H, start, frame, level, over, report, debug};
    return app_main(&fruit, argc, argv);
}
