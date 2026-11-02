#include "gfx_hw.h"
#include "assets.h"

#define DISPLAY ((volatile uint32_t *)0x30000000)
/* 各区的字偏移 (docs/display.md 的字节偏移 / 4) */
#define REG 0x00000
#define IMG (0x02000 / 4)
#define SPR (0x04000 / 4)
#define MAP (0x10000 / 4)
#define TEXT (0x20000 / 4)
#define FONT (0x30000 / 4)
#define IMAGE_MAX 1024
enum { CTRL, BACKDROP, CLIP, WINDOW, SCROLL, FADE, SPRITE_N, COMMIT, STATUS, FRAME, LINE_MAX, OVERRUN, DROPPED };

extern const uint8_t display_pack[]; /* refmodel.py firmware: (偏移, 个数, 数据...) 段, 0xFFFFFFFF 结尾; lz_pack 压缩 */
extern const uint8_t display_font[128 * 16];

static gfx_sprite_t sprites[GFX_HW_SPRITES];
static gfx_sprite_t spare; /* 表满时给的占位 */
static uint32_t sprite_n;
static uint32_t ctrl = 1, backdrop, clip = GFX_W << 16, window, scroll, fade;

static void reg(uint32_t r, uint32_t v)
{
    DISPLAY[REG + r] = v;
}

/* 解出来的字照段格式写进显示: 偏移 -> 个数 -> 数据; 读到结尾标记返回 1 */
static int put_word(uint32_t w)
{
    static volatile uint32_t *p;
    static uint32_t n, state;
    if (state == 0) {
        if (w == 0xFFFFFFFF)
            return 1;
        p = DISPLAY + w / 4;
        state = 1;
    } else if (state == 1) {
        n = w;
        state = n ? 2 : 0;
    } else {
        *p++ = w;
        if (--n == 0)
            state = 0;
    }
    return 0;
}

/* 解 refmodel.py 的 lz_pack: 头字节 < 0x80 = 跟 t+1 个原样字节, 否则从 d 字节前复制 (t & 0x7F) + 3 个。
 * 显示的内存读不回来, 所以最近 4 KB 输出留在栈上的环里 (只开机用一次) */
static void unpack(const uint8_t *s)
{
    uint8_t ring[4096];
    uint32_t o = 0, w = 0;
    for (;;) {
        uint32_t t = *s++, n, d = 0;
        if (t < 0x80) {
            n = t + 1;
        } else {
            n = (t & 0x7F) + 3;
            d = s[0] | (uint32_t)s[1] << 8;
            s += 2;
        }
        while (n--) {
            uint8_t b = d ? ring[(o - d) & 4095] : *s++;
            ring[o & 4095] = b;
            w |= (uint32_t)b << (8 * (o & 3));
            if ((++o & 3) == 0) {
                if (put_word(w))
                    return;
                w = 0;
            }
        }
    }
}

void gfx_hw_init(void)
{
    reg(CTRL, 0);
    unpack(display_pack);
    /* 素材之后的图案表项清 0 (= 没有这张图): 显示的 RAM 里可能是上一个程序留下的 (显示的内存读回总是 0, 不能先读) */
    for (uint32_t i = IMG_COUNT; i < IMAGE_MAX; i++)
        DISPLAY[IMG + i] = 0;
    for (uint32_t i = 0; i < 128 * 16; i++)
        DISPLAY[FONT + i] = display_font[i];
    for (uint32_t i = 0; i < GFX_MAP_W * GFX_MAP_H; i++)
        DISPLAY[MAP + i] = 0;
    gfx_text_clear();
    gfx_begin();
    gfx_hw_present();
}

void gfx_begin(void)
{
    sprite_n = 0;
    fade = 0;
}

gfx_sprite_t *gfx_sprite(int32_t x, int32_t y, uint32_t image)
{
    gfx_sprite_t *s = sprite_n < GFX_HW_SPRITES ? &sprites[sprite_n++] : &spare;
    *s = (gfx_sprite_t){
        .x = (int16_t)x, .y = (int16_t)y, .image = (uint16_t)image, .alpha = GFX_ALPHA_MAX, .scale = GFX_SCALE_1};
    return s;
}

static uint32_t sat12(int32_t v)
{
    return (uint32_t)(v < -2048 ? -2048 : v > 2047 ? 2047 : v) & 0xFFF;
}

void gfx_hw_present(void)
{
    while (DISPLAY[REG + COMMIT] & 1) /* 上一帧还没换上去: 后台精灵表还不能动 */
        ;
    volatile uint32_t *p = DISPLAY + SPR;
    for (uint32_t i = 0; i < sprite_n; i++) {
        const gfx_sprite_t *s = &sprites[i];
        *p++ = (uint32_t)s->scale << 24 | sat12(s->y) << 12 | sat12(s->x); /* 先写 w0 再写 w1 */
        *p++ = (uint32_t)s->angle << 24 | (uint32_t)(s->alpha & 31) << 16 | (uint32_t)(s->flags & 63) << 10 |
               (s->image & 1023);
    }
    reg(CTRL, ctrl);
    reg(BACKDROP, backdrop);
    reg(CLIP, clip);
    reg(WINDOW, window);
    reg(SCROLL, scroll);
    reg(FADE, fade);
    reg(SPRITE_N, sprite_n);
    reg(COMMIT, 1);
}

uint32_t gfx_hw_line_max(void)
{
    return DISPLAY[REG + LINE_MAX];
}

uint32_t gfx_hw_overrun(void)
{
    return DISPLAY[REG + OVERRUN];
}

uint32_t gfx_hw_dropped(void)
{
    return DISPLAY[REG + DROPPED];
}

uint32_t gfx_hw_frame(void)
{
    return DISPLAY[REG + FRAME];
}

void gfx_backdrop(uint16_t rgb565)
{
    backdrop = rgb565;
}

void gfx_map(int32_t col, int32_t row, uint32_t image)
{
    DISPLAY[MAP + (row & (GFX_MAP_H - 1)) * GFX_MAP_W + (col & (GFX_MAP_W - 1))] = image;
}

void gfx_scroll(int32_t x, int32_t y)
{
    scroll = (uint32_t)(y & 511) << 16 | (uint32_t)(x & 511);
}

void gfx_clip(int32_t x0, int32_t x1)
{
    clip = (uint32_t)(x1 & 1023) << 16 | (uint32_t)(x0 & 1023);
}

void gfx_window(int32_t x, int32_t y)
{
    window = sat12(y) << 16 | sat12(x);
    ctrl |= 2;
}

void gfx_fade(uint16_t rgb565, uint32_t level)
{
    fade = (level < 16 ? level : 16) << 16 | rgb565;
}

void gfx_text_clear(void)
{
    for (uint32_t i = 0; i < GFX_TEXT_COLS * GFX_TEXT_ROWS; i++)
        DISPLAY[TEXT + i] = 0;
}

void gfx_text(int32_t col, int32_t row, uint32_t color, const char *s)
{
    if (row < 0 || row >= GFX_TEXT_ROWS)
        return;
    for (; *s && col < GFX_TEXT_COLS; s++, col++)
        if (col >= 0)
            DISPLAY[TEXT + row * GFX_TEXT_COLS + col] = (color & 15) << 8 | (uint8_t)*s;
}

void gfx_number(int32_t col, int32_t row, uint32_t color, uint32_t n, int32_t width)
{
    char buf[12];
    int32_t i = width < 11 ? width : 11;
    buf[i] = 0;
    do {
        buf[--i] = (char)('0' + n % 10);
        n /= 10;
    } while (n && i > 0);
    while (i > 0)
        buf[--i] = ' ';
    gfx_text(col, row, color, buf);
}
