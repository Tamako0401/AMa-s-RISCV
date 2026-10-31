#include "menu.h"
#include "gfx.h"

/* 菜单占的文字格: 画面中间 (文字层 160x45 格, 东方式游戏区是第 40~119 列) */
#define COL 52
#define WIDTH 56
#define ROW 12
#define ROWS 18

static const char *const input_names[INPUT_N] = {"keys", "point"};

const char *menu_input_name(uint8_t mode)
{
    return mode < INPUT_N ? input_names[mode] : "?";
}

/* 写一行, 不够 WIDTH 格的用空格补齐 */
static void line(int32_t row, uint32_t color, const char *s)
{
    char buf[WIDTH + 1];
    int32_t i = 0;
    for (; s && s[i] && i < WIDTH; i++)
        buf[i] = s[i];
    for (; i < WIDTH; i++)
        buf[i] = ' ';
    buf[i] = 0;
    gfx_text(COL, ROW + row, color, buf);
}

/* 把 s 接到 buf 的 *n 处 */
static void cat(char *buf, int32_t *n, const char *s)
{
    while (*s && *n < WIDTH)
        buf[(*n)++] = *s++;
    buf[*n] = 0;
}

static void cat_num(char *buf, int32_t *n, int32_t v)
{
    char t[12];
    int32_t i = 11;
    uint32_t u = v < 0 ? (uint32_t)-v : (uint32_t)v;
    t[i] = 0;
    do {
        t[--i] = (char)('0' + u % 10);
        u /= 10;
    } while (u);
    if (v < 0)
        t[--i] = '-';
    cat(buf, n, t + i);
}

void menu_open(menu_t *m, int in_game)
{
    m->item = 0;
    m->in_game = (uint8_t)(in_game != 0);
}

void menu_close(void)
{
    for (int32_t r = 0; r < ROWS; r++)
        line(r, GFX_WHITE, "");
}

int menu_frame(menu_t *m, const pad_t *pad, uint8_t *mode, const menu_info_t *info)
{
    int32_t items = m->in_game ? 3 : 2;
    uint32_t p = pad->pressed;
    if (p & PAD_MENU)
        return MENU_RESUME;
    if (p & PAD_UP)
        m->item = (uint8_t)((m->item + items - 1) % items);
    if (p & PAD_DOWN)
        m->item = (uint8_t)((m->item + 1) % items);
    if (m->item == 1 && (p & (PAD_LEFT | PAD_RIGHT | PAD_A | PAD_CLICK)))
        *mode = (uint8_t)((*mode + 1) % INPUT_N);
    else if (p & (PAD_A | PAD_CLICK)) {
        if (m->item == 0)
            return MENU_RESUME;
        if (m->item == 2)
            return MENU_TITLE;
    }

    char buf[WIDTH + 1];
    int32_t n;
    line(0, GFX_WHITE, "                     PAUSED");
    line(1, GFX_WHITE, "");
    line(2, m->item == 0 ? GFX_YELLOW : GFX_LIGHT_GRAY, m->item == 0 ? "  > resume" : "    resume");
    n = 0;
    buf[0] = 0;
    cat(buf, &n, m->item == 1 ? "  > input: < " : "    input: < ");
    cat(buf, &n, menu_input_name(*mode));
    cat(buf, &n, " >");
    line(3, m->item == 1 ? GFX_YELLOW : GFX_LIGHT_GRAY, buf);
    line(4, m->item == 2 ? GFX_YELLOW : GFX_LIGHT_GRAY,
         !m->in_game    ? ""
         : m->item == 2 ? "  > back to title"
                        : "    back to title");
    line(5, GFX_WHITE, "");
    line(6, GFX_GRAY,
         *mode == INPUT_KEYS ? "    keys: arrows / wasd move, A bomb / slash"
                             : "    point: mouse or hand; left = A, right = B");
    line(7, GFX_GRAY, "    up/down choose, A ok, MENU back, RST restart");
    line(8, GFX_WHITE, "");

    /* 调试信息 */
    n = 0;
    buf[0] = 0;
    cat(buf, &n, "    mouse: ");
    if (pad->mouse) {
        cat_num(buf, &n, pad->mx);
        cat(buf, &n, ", ");
        cat_num(buf, &n, pad->my);
        cat(buf, &n, pad->held & PAD_CLICK ? "  L" : "");
        cat(buf, &n, pad->held & PAD_RCLICK ? "  R" : "");
    } else
        cat(buf, &n, "none");
    line(9, GFX_GRAY, buf);
    n = 0;
    buf[0] = 0;
    cat(buf, &n, "    hand: ");
    const hand_t *h = info->hand;
    if (h && h->found) {
        cat_num(buf, &n, h->x >> 8);
        cat(buf, &n, ", ");
        cat_num(buf, &n, h->y >> 8);
        cat(buf, &n, h->fist ? "  fist" : "  open");
    } else
        cat(buf, &n, "none");
    line(10, GFX_GRAY, buf);
    n = 0;
    buf[0] = 0;
    cat(buf, &n, "    cpu: ");
    cat_num(buf, &n, (int32_t)info->cpu);
    cat(buf, &n, " cycles/frame (of 833k)");
    line(11, GFX_GRAY, buf);
    return MENU_STAY;
}
