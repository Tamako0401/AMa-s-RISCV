#include "fruit.h"
#include "sound.h"
#include "assets.h"
#include "fixed.h"
#include "gfx.h"

#define FPS 60
#define LIVES 3
#define RESTART_HOLD FPS /* 游戏结束后张开手几帧重开 */
#define GRAVITY 40       /* Q8 像素 / 帧^2 (约 560 像素 / 秒^2) */
#define BLADE_MIN Q8(5)  /* 刀每帧至少移动这么多 (300 像素 / 秒) 才切得开 */
#define STROKE_STEP 12   /* 刀光每隔几个点放一笔 (一笔 16 点长, 两头 4 点淡出, 叠起来接上) */
#define STAIN_FRAMES 180 /* 果汁印留几帧 */
#define COMBO_MIN 3      /* 一刀切开几个算连击 */
#define FLASH_FRAMES 30
#define WINDOW_X 0 /* 摄像头小窗在左上角 */
#define WINDOW_Y 0

enum { APPLE, ORANGE, MELON, BOMB }; /* 水果的种类 */
static const uint8_t fruit_r[] = {13, 13, 27, 12};
static const uint16_t whole_image[] = {IMG_APPLE, IMG_ORANGE, IMG_MELON, IMG_BOMB};
static const uint16_t half_image[] = {IMG_APPLE_HALF, IMG_ORANGE_HALF, IMG_MELON_HALF, IMG_BOMB};
static const uint16_t juice_image[] = {IMG_JUICE_ORANGE, IMG_JUICE_ORANGE, IMG_JUICE_RED, IMG_SPARK};
static const uint16_t drop_image[] = {IMG_DROP_CREAM, IMG_DROP_ORANGE, IMG_DROP_RED, IMG_SPARK};
static const uint16_t stain_image[] = {IMG_STAIN_CREAM, IMG_STAIN_ORANGE, IMG_STAIN_RED, IMG_SPARK};

void fruit_init(fruit_t *g, uint32_t seed)
{
    sound_reset();
    sound_play(SFX_START);
    *g = (fruit_t){0};
    g->lives = LIVES;
    g->rng = seed ? seed : 1;
    g->next_wave = FPS;
}

void fruit_screen(void)
{
    gfx_backdrop(0);
    gfx_clip(0, FRUIT_W);
    for (int32_t row = 0; row < GFX_MAP_H; row++)
        for (int32_t col = 0; col < GFX_MAP_W; col++) {
            /* 木板宽 4 格 (32 点), 每块板的最右一格画缝; 偶尔有个节疤 */
            uint32_t knot = (uint32_t)(col * 7 + row * 13) % 23 == 0;
            gfx_map(col, row, (col % 4 == 3 ? IMG_WOOD1 : IMG_WOOD0) + 2 * knot);
        }
    gfx_scroll(0, 0);
    gfx_window(WINDOW_X, WINDOW_Y);
    gfx_text_clear();
}

int32_t fruit_level(const fruit_t *g)
{
    return 1 + (int32_t)(g->t / (20 * FPS)) + g->level_bonus; /* 每 20 秒加一级 */
}

static uint32_t rand_range(fruit_t *g, uint32_t n)
{
    return fx_rand(&g->rng) % n;
}

/* 一波: 从下面抛上来几个, 越往后越多、越密 */
static void wave(fruit_t *g)
{
    if (g->t < g->next_wave)
        return;
    int32_t level = fruit_level(g);
    int32_t gap = 100 - 6 * level;
    g->next_wave = g->t + (uint32_t)(gap < 36 ? 36 : gap);
    int32_t most = 1 + (level < 10 ? level : 10) / 2;
    int32_t n = 1 + (int32_t)rand_range(g, (uint32_t)most);
    int32_t bomb = level >= 2 && rand_range(g, 5) == 0 ? (int32_t)rand_range(g, (uint32_t)n) : -1;
    for (int32_t i = 0; i < n && g->fruit_n < FRUIT_MAX; i++) {
        fruit_obj_t *f = &g->fruits[g->fruit_n++];
        *f = (fruit_obj_t){0};
        f->x = Q8(80 + (int32_t)rand_range(g, FRUIT_W - 160));
        f->y = Q8(FRUIT_H + 24);
        /* 往中间偏, 约 1.5 秒飞到最高 */
        f->vx = (Q8(FRUIT_W / 2) - f->x) / 90 + (int32_t)rand_range(g, 129) - 64;
        f->vy = -(Q8(7.5) + (int32_t)rand_range(g, Q8(2)));
        f->spin = (int16_t)((200 + (int32_t)rand_range(g, 400)) * (rand_range(g, 2) ? 1 : -1));
        f->kind = (uint8_t)(i == bomb ? BOMB : rand_range(g, 6) == 0 ? MELON : rand_range(g, 2) ? APPLE : ORANGE);
    }
}

/* 刀: 记下这一帧的位置; 最近 3 帧移动够快才算在切 */
static void blade(fruit_t *g, const fruit_control_t *in)
{
    if (!in->has_pos) { /* 看不见手: 刀光从尾巴开始消失 */
        if (g->trail_n)
            g->trail_n--;
        g->blade = 0;
        return;
    }
    for (int32_t i = FRUIT_TRAIL - 1; i > 0; i--) {
        g->trail[i][0] = g->trail[i - 1][0];
        g->trail[i][1] = g->trail[i - 1][1];
    }
    g->trail[0][0] = in->x;
    g->trail[0][1] = in->y;
    if (g->trail_n < FRUIT_TRAIL)
        g->trail_n++;
    /* 手的结果约 30 次 / 秒, 游戏 60 帧 / 秒: 一帧的移动可能是 0, 所以看 3 帧 */
    int32_t k = g->trail_n - 1 < 3 ? g->trail_n - 1 : 3;
    if (k == 0) {
        g->blade = 0;
        return;
    }
    int32_t dx = fx_abs(g->trail[0][0] - g->trail[k][0]), dy = fx_abs(g->trail[0][1] - g->trail[k][1]);
    int32_t len = dx > dy ? dx + dy / 2 : dy + dx / 2; /* 不开方的近似长度 */
    g->blade = len >= BLADE_MIN * k;
}

/* 线段 a -> b 离点 p 的距离小于 r 吗? 坐标 Q8。先用方框粗筛, 近了才乘 */
static int touches(fruit_t *g, const int32_t *a, const int32_t *b, int32_t px, int32_t py, int32_t r)
{
    int32_t x0 = a[0] < b[0] ? a[0] : b[0], x1 = a[0] ^ b[0] ^ x0;
    int32_t y0 = a[1] < b[1] ? a[1] : b[1], y1 = a[1] ^ b[1] ^ y0;
    if (px < x0 - r || px > x1 + r || py < y0 - r || py > y1 + r)
        return 0;
    g->cut_tests++;
    /* 换成 Q4 再算, 平方用 64 位 */
    int64_t ex = (b[0] - a[0]) >> 4, ey = (b[1] - a[1]) >> 4;
    int64_t qx = (px - a[0]) >> 4, qy = (py - a[1]) >> 4, rr = (int64_t)(r >> 4) * (r >> 4);
    int64_t len2 = ex * ex + ey * ey, dot = qx * ex + qy * ey;
    if (dot <= 0) /* 最近的是 a */
        return qx * qx + qy * qy < rr;
    if (dot >= len2) /* 最近的是 b */
        return (qx - ex) * (qx - ex) + (qy - ey) * (qy - ey) < rr;
    int64_t cross = qx * ey - qy * ex; /* 到直线的距离 = cross / |e| */
    return cross * cross < rr * len2;
}

static void splash(fruit_t *g, const fruit_obj_t *f, uint32_t dir)
{
    /* 两半: 刀口顺着刀的方向, 往刀的两侧分开 */
    int32_t nx = fx_cos(dir + ANGLE_TURN / 4) * 3 >> 7,
            ny = fx_sin(dir + ANGLE_TURN / 4) * 3 >> 7; /* 1.5 像素 / 帧, Q8 */
    for (int32_t side = 0; side < 2 && g->piece_n < FRUIT_PIECES; side++) {
        fruit_obj_t *p = &g->pieces[g->piece_n++];
        *p = *f;
        p->vx = f->vx + (side ? nx : -nx);
        p->vy = f->vy + (side ? ny : -ny);
        p->angle = (uint16_t)(dir - ANGLE_TURN / 4); /* 半个的图刀口是竖的 (朝下 = 角度 1/4 圈) */
        p->spin = (int16_t)(side ? 300 : -300);
        p->flip = (uint8_t)side;
    }
    /* 汁水: 8 团果汁 (不透明, 飞得远, 慢慢淡出) + 8 个光点 */
    for (int32_t i = 0; i < 16 && g->juice_n < FRUIT_JUICE; i++) {
        fruit_obj_t *j = &g->juice[g->juice_n++];
        uint32_t a = fx_rand(&g->rng);
        int32_t drop = i < 8;
        int32_t speed = (drop ? Q8(1.5) : Q8(1)) + (int32_t)rand_range(g, drop ? Q8(3) : Q8(2));
        *j = (fruit_obj_t){.x = f->x, .y = f->y, .kind = f->kind, .flip = (uint8_t)drop};
        j->vx = speed * fx_cos(a) >> 14;
        j->vy = (speed * fx_sin(a) >> 14) - Q8(1);
        j->life = (uint8_t)((drop ? 30 : 20) + rand_range(g, 16));
        j->angle = (uint16_t)fx_rand(&g->rng);
    }
    if (f->kind == BOMB)
        return;
    /* 木板上留一摊果汁印 */
    if (g->stain_n == FRUIT_STAINS) {
        for (int32_t i = 1; i < FRUIT_STAINS; i++)
            g->stains[i - 1] = g->stains[i];
        g->stain_n--;
    }
    g->stains[g->stain_n++] =
        (fruit_obj_t){.x = f->x, .y = f->y, .kind = f->kind, .life = STAIN_FRAMES, .angle = (uint16_t)fx_rand(&g->rng)};
}

static void lose(fruit_t *g)
{
    if (g->invincible)
        return;
    if (g->lives)
        g->lives--;
    g->over = g->lives == 0;
    if (g->over)
        sound_play(SFX_END);
}

static void cut(fruit_t *g)
{
    if (!g->blade) {
        if (g->combo >= COMBO_MIN) { /* 一刀结束: 连击加分 */
            g->score += g->combo;
            g->combo_n = g->combo;
            g->combo_show = FPS;
        }
        if (g->combo > g->best_combo)
            g->best_combo = g->combo;
        g->combo = 0;
        return;
    }
    const int32_t *a = g->trail[1], *b = g->trail[0];
    if (a[0] == b[0] && a[1] == b[1]) /* 这一帧没动 (手的结果还没更新) */
        return;
    uint32_t dir = fx_atan2(b[1] - a[1], b[0] - a[0]);
    uint16_t kept = 0;
    for (uint16_t i = 0; i < g->fruit_n; i++) {
        fruit_obj_t f = g->fruits[i];
        if (!touches(g, a, b, f.x, f.y, Q8(fruit_r[f.kind]))) {
            g->fruits[kept++] = f;
            continue;
        }
        splash(g, &f, dir);
        if (f.kind == BOMB) {
            sound_play(SFX_FRUIT_BOMB);
            g->bombs_hit++;
            g->flash = FLASH_FRAMES;
            lose(g);
            continue;
        }
        sound_play(SFX_CUT);
        g->cut++;
        g->score += f.kind == MELON ? 2 : 1;
        g->combo++;
        g->combo_x = f.x;
        g->combo_y = f.y;
    }
    g->fruit_n = kept;
}

/* 一组东西按重力飞, 掉出画面下面就删掉; 返回删掉的水果 (不含炸弹) 有几个 */
static int32_t fall(fruit_obj_t *objs, uint16_t *n, int32_t gravity, int count_misses)
{
    int32_t missed = 0;
    uint16_t kept = 0;
    for (uint16_t i = 0; i < *n; i++) {
        fruit_obj_t o = objs[i];
        o.vy += gravity;
        o.x += o.vx;
        o.y += o.vy;
        o.angle = (uint16_t)(o.angle + o.spin);
        if (o.life && --o.life == 0)
            continue;
        if (o.y > Q8(FRUIT_H + 40) && o.vy > 0) {
            missed += count_misses && o.kind != BOMB;
            continue;
        }
        objs[kept++] = o;
    }
    *n = kept;
    return missed;
}

void fruit_step(fruit_t *g, const fruit_control_t *in)
{
    g->cut_tests = 0;
    if (g->combo_show)
        g->combo_show--;
    if (g->flash)
        g->flash--;
    if (g->over) {
        g->hold = in->open ? g->hold + 1 : 0;
        blade(g, in);
        if (g->hold < RESTART_HOLD && !in->restart)
            return;
    }
    if (g->over || in->restart) {
        uint8_t bonus = g->level_bonus, invincible = g->invincible;
        fruit_init(g, g->rng);
        g->level_bonus = bonus;
        g->invincible = invincible;
        return;
    }
    g->t++;
    wave(g);
    int was_blade = g->blade;
    blade(g, in);
    if (g->blade && !was_blade)
        sound_play(SFX_SLASH);
    cut(g);
    for (int32_t m = fall(g->fruits, &g->fruit_n, GRAVITY, 1); m > 0; m--) {
        sound_play(SFX_MISS);
        g->missed++;
        lose(g);
    }
    fall(g->pieces, &g->piece_n, GRAVITY, 0);
    fall(g->juice, &g->juice_n, GRAVITY / 2, 0);
    fall(g->stains, &g->stain_n, 0, 0);
}

void fruit_control_from_hand(const hand_t *hand, fruit_control_t *in)
{
    *in = (fruit_control_t){0};
    in->has_pos = hand->valid && hand->found;
    in->x = hand->x;
    in->y = hand->y;
    in->open = hand->found && !hand->fist;
}

/* ---- 画 ---- */

static gfx_sprite_t *obj_sprite(const fruit_obj_t *o, uint32_t image)
{
    gfx_sprite_t *s = gfx_sprite(o->x >> 8, o->y >> 8, image);
    s->flags = GFX_AFFINE | (o->flip ? GFX_FLIP_X : 0);
    s->angle = (uint8_t)(o->angle >> 8);
    s->scale = GFX_SCALE_1;
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

static void draw_hud(const fruit_t *g, const hand_t *hand)
{
    const int32_t c = 140;
    text_field(c, 1, GFX_GRAY, "SCORE", 16);
    gfx_number(c, 2, GFX_WHITE, g->score, 8);
    text_field(c, 4, GFX_GRAY, "LIFE", 16);
    text_field(c, 5, GFX_LIGHT_RED, g->lives >= 3 ? "* * *" : g->lives == 2 ? "* *" : g->lives ? "*" : "", 16);
    text_field(c, 7, GFX_GRAY, "LEVEL", 16);
    gfx_number(c, 8, GFX_WHITE, (uint32_t)fruit_level(g), 3);

    /* 小窗 (文字 0~7 行) 下面写手的状态 */
    text_field(1, 8, GFX_YELLOW, !hand->found ? "hand: none" : hand->fist ? "hand: FIST" : "hand: open", 16);

    /* 连击字样: 写在最后一个切开的水果附近 (文字格 8x16 = 画面 4x8 点) */
    static int32_t last_col, last_row; /* 上次写的地方, 下次擦掉 */
    text_field(last_col, last_row, GFX_WHITE, "", 10);
    if (g->combo_show) {
        last_col = (g->combo_x >> 8) / 4 - 4;
        last_row = (g->combo_y >> 8) / 8 - 3;
        last_col = last_col < 0 ? 0 : last_col > 150 ? 150 : last_col;
        last_row = last_row < 0 ? 0 : last_row;
        text_field(last_col, last_row, GFX_YELLOW, "COMBO", 6);
        gfx_number(last_col + 6, last_row, GFX_YELLOW, g->combo_n, 2);
    }

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

/* 刀光: 相邻两帧的位置之间, 顺着这一段的方向摆几笔 (旋转的细长发光图, 加法), 首尾叠起来连成线; 越旧越细越淡 */
static void draw_blade(const fruit_t *g)
{
    for (int32_t i = 0; i + 1 < g->trail_n; i++) {
        const int32_t *a = g->trail[i], *b = g->trail[i + 1];
        int32_t dx = fx_abs(b[0] - a[0]), dy = fx_abs(b[1] - a[1]);
        int32_t len = (dx > dy ? dx + dy / 2 : dy + dx / 2) >> 8;
        if (len == 0) /* 这一帧手没动 (结果还没更新) */
            continue;
        int32_t scale = GFX_SCALE_1 - i * 8 / FRUIT_TRAIL; /* 最新的原大, 最旧的约一半 */
        int32_t n = len * GFX_SCALE_1 / (STROKE_STEP * scale) + 1;
        n = n > 16 ? 16 : n;
        uint8_t angle = (uint8_t)(fx_atan2(b[1] - a[1], b[0] - a[0]) >> 8);
        for (int32_t k = 0; k < n; k++) {
            int32_t x = a[0] + (b[0] - a[0]) * (2 * k + 1) / (2 * n), y = a[1] + (b[1] - a[1]) * (2 * k + 1) / (2 * n);
            gfx_sprite_t *s = gfx_sprite(x >> 8, y >> 8, IMG_STREAK);
            s->flags = GFX_ADD | GFX_ALPHA | GFX_AFFINE;
            s->alpha = (uint8_t)(GFX_ALPHA_MAX - i * GFX_ALPHA_MAX / FRUIT_TRAIL);
            s->angle = angle;
            s->scale = (uint8_t)scale;
        }
    }
}

void fruit_draw(const fruit_t *g, const hand_t *hand)
{
    gfx_begin();
    for (uint16_t i = 0; i < g->stain_n; i++) { /* 果汁印在最下面, 最后 1 秒淡出 */
        const fruit_obj_t *st = &g->stains[i];
        gfx_sprite_t *s = obj_sprite(st, stain_image[st->kind]);
        s->flags |= GFX_ALPHA;
        s->alpha = (uint8_t)(st->life >= 60 ? 12 : st->life * 12 / 60);
    }
    for (uint16_t i = 0; i < g->fruit_n; i++) {
        const fruit_obj_t *f = &g->fruits[i];
        obj_sprite(f, whole_image[f->kind]);
        if (f->kind == BOMB && g->t / 3 % 2) { /* 引信的火花, 闪 */
            gfx_sprite_t *s = gfx_sprite((f->x >> 8) + (fx_sin(f->angle) * 13 >> 14),
                                         (f->y >> 8) - (fx_cos(f->angle) * 13 >> 14), IMG_SPARK);
            s->flags = GFX_ADD;
        }
    }
    for (uint16_t i = 0; i < g->piece_n; i++)
        obj_sprite(&g->pieces[i], half_image[g->pieces[i].kind]);
    for (uint16_t i = 0; i < g->juice_n; i++) {
        const fruit_obj_t *j = &g->juice[i];
        uint8_t fade = (uint8_t)(j->life < GFX_ALPHA_MAX ? j->life : GFX_ALPHA_MAX);
        if (j->flip) { /* 果汁团: 半透明淡出 */
            gfx_sprite_t *s = gfx_sprite(j->x >> 8, j->y >> 8, drop_image[j->kind]);
            s->flags = GFX_ALPHA | GFX_FLIP_X * (j->angle & 1) | GFX_FLIP_Y * (j->angle >> 1 & 1);
            s->alpha = fade;
        } else {
            gfx_sprite_t *s = gfx_sprite(j->x >> 8, j->y >> 8, juice_image[j->kind]);
            s->flags = GFX_ADD | GFX_ALPHA;
            s->alpha = fade;
        }
    }
    draw_blade(g);

    if (hand->valid) { /* 小窗里标出手 */
        int32_t wx, wy;
        hand_to_window(hand->x, hand->y, FRUIT_W, FRUIT_H, &wx, &wy);
        gfx_sprite(WINDOW_X + wx, WINDOW_Y + wy, hand->fist ? IMG_HITBOX : IMG_SPARK);
    }
    if (g->flash)
        gfx_fade(0xFFFF, (uint32_t)g->flash * GFX_ALPHA_MAX / FLASH_FRAMES);
    draw_hud(g, hand);
}
