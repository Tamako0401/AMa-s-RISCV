#include "touhou.h"
#include "sound.h"
#include "bgm.h"
#include "assets.h"
#include "fixed.h"
#include "gfx.h"

/* play.py 的画面高 240, 这里游戏区高 360: 长度、速度都乘 1.5 */
#define FPS 60
#define SPEED(px_per_s) ((px_per_s) * 256 / FPS) /* 像素 / 秒 -> Q8 像素 / 帧 */
#define DEG(rad) ((uint32_t)((rad) * 10430.378)) /* 弧度 -> angle16 (编译时算好) */

#define LIVES 3
#define BOMBS 3              /* 每条命几个 bomb */
#define INVINCIBLE (2 * FPS) /* 被击中或放 bomb 后无敌几帧 */
#define RESTART_HOLD FPS     /* 游戏结束后张开手几帧重开 */
#define PLAYER_R 3           /* 自机判定点半径 (东方式: 判定点比画出来的飞机小得多) */
#define MARGIN 16            /* 弹飞出游戏区多远删掉 */
#define BOSS_Y 60
#define BOMB_FRAMES 30 /* bomb 光环放多久 */
#define WINDOW_X 0     /* 摄像头小窗放在左侧栏上部 */
#define WINDOW_Y 16

enum { SMALL, ORB, RICE }; /* 弹的种类 */
static const uint8_t bullet_r[] = {3, 6, 3};
static const uint16_t bullet_image[] = {IMG_BULLET, IMG_ORB, IMG_RICE};

void touhou_init(touhou_t *g, uint32_t seed)
{
    sound_reset();
    sound_play(SFX_START);
    *g = (touhou_t){0};
    g->px = Q8(PLAY_W / 2);
    g->py = Q8(PLAY_H * 4 / 5);
    g->lives = LIVES;
    g->bombs = BOMBS;
    g->rng = seed ? seed : 1;
    gfx_portrait_load(0);
    bgm_play(0); /* 进关示范: 缺包/缺素材照常玩 */
}

void touhou_screen(void)
{
    uint32_t rng = 12345;
    gfx_backdrop(0x0841); /* 侧栏: 很暗的灰 */
    gfx_clip(PLAY_X, PLAY_X + PLAY_W);
    for (int32_t row = 0; row < GFX_MAP_H; row++)
        for (int32_t col = 0; col < GFX_MAP_W; col++) {
            uint32_t r = fx_rand(&rng) % 16; /* 大多是空的, 偶尔几颗星 */
            gfx_map(col, row, r < 13 ? IMG_TILE0 : IMG_TILE1 + r % 3);
        }
    gfx_window(WINDOW_X, WINDOW_Y);
    gfx_text_clear();
}

int32_t touhou_level(const touhou_t *g)
{
    return 1 + (int32_t)(g->t / (30 * FPS)) + g->level_bonus; /* 每 30 秒加一级 */
}

static void boss_pos(const touhou_t *g, int32_t *x, int32_t *y)
{
    *x = Q8(PLAY_W / 2) + 150 * fx_sin(g->t * 122) / 64; /* 左右 150 点, 每秒 0.7 弧度; Q14 * 150 / 64 = Q8 */
    *y = Q8(BOSS_Y);
}

static void fire(touhou_t *g, uint32_t angle, int32_t speed, uint8_t kind)
{
    if (g->bullet_n >= TOUHOU_BULLETS)
        return;
    bullet_t *b = &g->bullets[g->bullet_n++];
    boss_pos(g, &b->x, &b->y);
    b->vx = speed * fx_cos(angle) >> 14;
    b->vy = speed * fx_sin(angle) >> 14;
    b->kind = kind;
    b->angle = (uint8_t)(angle >> 8);
}

/* 每 5 秒换一种弹幕; 级别越高越多、越快 */
static void pattern(touhou_t *g)
{
    if (g->t < g->next_fire)
        return;
    int32_t level = touhou_level(g);
    switch (g->t / (5 * FPS) % 3) {
    case 0: { /* 圆环: 一圈同时射出 */
        int32_t n = 12 + 4 * level;
        uint32_t start = fx_rand(&g->rng);
        for (int32_t i = 0; i < n; i++)
            fire(g, start + (uint32_t)(ANGLE_TURN * i / n), SPEED(75 + 15 * level), ORB);
        g->next_fire = g->t + 48;
        break;
    }
    case 1: { /* 自机狙: 对准自机的一小扇, 米弹朝着飞行方向 */
        int32_t bx, by;
        boss_pos(g, &bx, &by);
        uint32_t aim = fx_atan2(g->py - by, g->px - bx);
        for (int32_t i = -2; i <= 2; i++)
            fire(g, aim + (uint32_t)(i * (int32_t)DEG(0.25)), SPEED(120 + 15 * level), RICE);
        g->next_fire = g->t + 36;
        break;
    }
    default: /* 螺旋: 一直转着射 */
        for (int32_t i = 0; i < level; i++)
            fire(g, g->spiral + (uint32_t)(ANGLE_TURN * i / level), SPEED(90), SMALL);
        g->spiral += DEG(0.35);
        g->next_fire = g->t + 4;
        break;
    }
}

static void bomb(touhou_t *g)
{
    if (g->bombs == 0 || g->over)
        return;
    sound_play(SFX_BOMB);
    g->bombs--;
    g->bombs_used++;
    g->bullet_n = 0;
    g->invincible = INVINCIBLE;
    g->bomb_t = 1;
    g->bomb_x = g->px;
    g->bomb_y = g->py;
}

static void shoot(touhou_t *g)
{
    if (g->t >= g->next_shot && g->shot_n < TOUHOU_SHOTS) {
        g->shots[g->shot_n][0] = g->px;
        g->shots[g->shot_n][1] = g->py - Q8(8);
        sound_play(SFX_SHOT);
        g->shot_n++;
        g->next_shot = g->t + 5;
    }
    int32_t bx, by;
    boss_pos(g, &bx, &by);
    uint16_t kept = 0;
    for (uint16_t i = 0; i < g->shot_n; i++) {
        int32_t *s = g->shots[i];
        s[1] -= SPEED(450);
        if (fx_abs(s[0] - bx) < Q8(24) && fx_abs(s[1] - by) < Q8(18)) {
            sound_play(SFX_ENEMY_HIT);
            g->score += 10;
            if (g->spark_n < TOUHOU_SPARKS) {
                int32_t *k = g->sparks[g->spark_n++];
                k[0] = s[0];
                k[1] = s[1];
                k[2] = 12;
            }
        } else if (s[1] > 0) {
            g->shots[kept][0] = s[0];
            g->shots[kept][1] = s[1];
            kept++;
        }
    }
    g->shot_n = kept;

    kept = 0;
    for (uint16_t i = 0; i < g->spark_n; i++) {
        int32_t *k = g->sparks[i];
        if (--k[2] > 0) {
            g->sparks[kept][0] = k[0];
            g->sparks[kept][1] = k[1] - Q8(1);
            g->sparks[kept][2] = k[2];
            kept++;
        }
    }
    g->spark_n = kept;
}

/* 敌弹移动, 出界删掉; 返回有没有碰到自机 */
static int move_bullets(touhou_t *g)
{
    int hit = 0;
    uint16_t kept = 0;
    for (uint16_t i = 0; i < g->bullet_n; i++) {
        bullet_t b = g->bullets[i];
        b.x += b.vx;
        b.y += b.vy;
        if (b.x < Q8(-MARGIN) || b.x > Q8(PLAY_W + MARGIN) || b.y < Q8(-MARGIN) || b.y > Q8(PLAY_H + MARGIN))
            continue;
        g->bullets[kept++] = b;
        /* 先用方框粗筛, 近了才算距离 (板上乘法慢) */
        int32_t r = Q8(PLAYER_R + bullet_r[b.kind]);
        int32_t dx = b.x - g->px, dy = b.y - g->py;
        if (!g->invincible && (g->t & 7) == 0 && fx_abs(dx) < r + Q8(10) && fx_abs(dy) < r + Q8(10) &&
            (fx_abs(dx) >= r || fx_abs(dy) >= r))
            sound_play(SFX_GRAZE);
        if (fx_abs(dx) < r && fx_abs(dy) < r) {
            g->work.hit_tests++;
            dx >>= 4; /* Q4, 平方不溢出 */
            dy >>= 4;
            if (dx * dx + dy * dy < (r >> 4) * (r >> 4))
                hit = 1;
        }
    }
    g->work.bullets_moved += g->bullet_n;
    g->bullet_n = kept;
    return hit;
}

void touhou_step(touhou_t *g, const control_t *in)
{
    g->work = (touhou_work_t){0};
    if (g->over) {
        g->hold = in->open ? g->hold + 1 : 0;
        if (g->hold >= RESTART_HOLD || in->restart) {
            uint8_t bonus = g->level_bonus;
            touhou_init(g, g->rng);
            g->level_bonus = bonus;
        }
        return;
    }
    if (in->restart) {
        uint8_t bonus = g->level_bonus;
        touhou_init(g, g->rng);
        g->level_bonus = bonus;
        return;
    }
    g->t++;
    if (g->invincible)
        g->invincible--;
    if (g->bomb_t && ++g->bomb_t > BOMB_FRAMES)
        g->bomb_t = 0;
    if (in->has_pos) { /* 绝对位置: 自机直接到手的位置 */
        g->px = in->x;
        g->py = in->y;
    }
    if (in->bomb)
        bomb(g);

    shoot(g);
    pattern(g);
    if (move_bullets(g) && !g->invincible) {
        sound_play(SFX_PLAYER_HIT);
        g->hits++;
        g->lives--;
        g->bombs = BOMBS;
        g->bullet_n = 0;
        g->invincible = INVINCIBLE;
        g->over = g->lives == 0;
        if (g->over)
            sound_play(SFX_END);
    }
}

void touhou_control_from_hand(const hand_t *hand, control_t *in)
{
    *in = (control_t){0};
    in->has_pos = hand->valid;
    in->x = hand->x;
    in->y = hand->y;
    in->bomb = hand->opened;
    in->open = hand->found && !hand->fist;
}

/* ---- 画 ---- */

static gfx_sprite_t *play_sprite(int32_t x, int32_t y, uint32_t image)
{
    gfx_sprite_t *s = gfx_sprite(PLAY_X + (x >> 8), y >> 8, image);
    s->flags = GFX_CLIP;
    return s;
}

/* 写一段文字, 不够 width 格的用空格补齐 (盖掉上次写的) */
static void text_field(int32_t col, int32_t row, uint32_t color, const char *s, int32_t width)
{
    char buf[48];
    int32_t i = 0;
    for (; s[i] && i < width && i < 47; i++)
        buf[i] = s[i];
    for (; i < width && i < 47; i++)
        buf[i] = ' ';
    buf[i] = 0;
    gfx_text(col, row, color, buf);
}

static void draw_hud(const touhou_t *g, const hand_t *hand)
{
    const int32_t c = 124; /* 右侧栏 (1280 宽的 960 往右) 第一列再空 4 格 */
    text_field(c, 3, GFX_GRAY, "SCORE", 12);
    gfx_number(c, 4, GFX_WHITE, g->score, 10);
    text_field(c, 6, GFX_GRAY, "PLAYER", 12);
    text_field(c, 7, GFX_LIGHT_RED, g->lives >= 3 ? "* * *" : g->lives == 2 ? "* *" : g->lives ? "*" : "", 12);
    text_field(c, 9, GFX_GRAY, "BOMB", 12);
    text_field(c, 10, GFX_LIGHT_GREEN, g->bombs >= 3 ? "* * *" : g->bombs == 2 ? "* *" : g->bombs ? "*" : "", 12);
    text_field(c, 12, GFX_GRAY, "LEVEL", 12);
    gfx_number(c, 13, GFX_WHITE, (uint32_t)touhou_level(g), 3);
    text_field(c, 15, GFX_GRAY, "TIME", 12);
    gfx_number(c, 16, GFX_WHITE, g->t / FPS, 4);
    text_field(c, 18, GFX_GRAY, "BULLETS", 12);
    gfx_number(c, 19, GFX_WHITE, g->bullet_n, 4);

    /* 左侧栏: 摄像头小窗 (画面 y 16~136, 即文字 2~16 行) 下面写手的状态 */
    text_field(4, 18, GFX_GRAY, "HAND", 12);
    text_field(4, 19, GFX_YELLOW, !hand->found ? "none" : hand->fist ? "FIST" : "open", 12);

    if (g->over) {
        text_field(60, 20, GFX_WHITE, "      GAME OVER", 40);
        text_field(60, 22, GFX_LIGHT_GRAY, "  open hand 1s to restart", 40);
        gfx_number(70, 23, GFX_YELLOW, g->hold * 100 / RESTART_HOLD, 3);
    } else {
        text_field(60, 20, GFX_WHITE, "", 40);
        text_field(60, 22, GFX_WHITE, "", 40);
        text_field(60, 23, GFX_WHITE, "", 40);
    }
}

void touhou_draw(const touhou_t *g, const hand_t *hand)
{
    gfx_begin();
    gfx_scroll(0, -(int32_t)(g->t / 2)); /* 背景慢慢往下流 */

    if (g->t < 120)
        gfx_portrait(PLAY_X + PLAY_W - 132, 130, 16);

    int32_t bx, by;
    boss_pos(g, &bx, &by);
    play_sprite(bx, by, IMG_BOSS);

    for (uint16_t i = 0; i < g->shot_n; i++) {
        gfx_sprite_t *s = play_sprite(g->shots[i][0], g->shots[i][1], IMG_SHOT);
        s->flags |= GFX_ALPHA;
        s->alpha = 10;
    }
    for (uint16_t i = 0; i < g->spark_n; i++) {
        gfx_sprite_t *s = play_sprite(g->sparks[i][0], g->sparks[i][1], IMG_SPARK);
        s->flags |= GFX_ADD;
    }

    /* 自机: 无敌时闪烁; 判定点 (白点) 画在最上面 */
    if (!g->invincible || g->t / 4 % 2)
        play_sprite(g->px, g->py, IMG_PLAYER);
    for (uint16_t i = 0; i < g->bullet_n; i++) {
        const bullet_t *b = &g->bullets[i];
        gfx_sprite_t *s = play_sprite(b->x, b->y, bullet_image[b->kind]);
        if (b->kind == RICE) {
            s->flags |= GFX_AFFINE;
            s->angle = b->angle;
            s->scale = GFX_SCALE_1;
        }
    }
    play_sprite(g->px, g->py, IMG_HITBOX);

    if (g->bomb_t) { /* bomb: 光环从自机处放大、变淡 */
        gfx_sprite_t *s = play_sprite(g->bomb_x, g->bomb_y, IMG_RING);
        s->flags |= GFX_AFFINE | GFX_ADD | GFX_ALPHA;
        s->scale = (uint8_t)(GFX_SCALE_1 + g->bomb_t * 2);
        s->alpha = (uint8_t)(GFX_ALPHA_MAX - g->bomb_t * GFX_ALPHA_MAX / (BOMB_FRAMES + 1));
    }

    /* 小窗里标出手在摄像头画面里的位置 (游戏区坐标反算回 160x120) */
    if (hand->valid) {
        int32_t wx, wy;
        hand_to_window(hand->x, hand->y, PLAY_W, PLAY_H, &wx, &wy);
        gfx_sprite(WINDOW_X + wx, WINDOW_Y + wy, hand->fist ? IMG_HITBOX : IMG_SPARK);
    }
    draw_hud(g, hand);
}
