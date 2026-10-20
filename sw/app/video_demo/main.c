/* video_demo: HDMI 出图演示。蓝底白框的背景, 左上角一个静止的球 (精灵 0), 下半屏 8 个球来回弹。
 * 仿真测试 tests/soc/video_tb.sv 核对静止部分。 */
#include "bsp.h"
#include "uart.h"
#include "video.h"
#include "board_hdmi.h"

/* 仿真时测试台把对这里的写当作准备好了 (sw/link.ld 把 .tohost 放在 RAM 开头); 上板没人看, 写了无害 */
volatile uint64_t tohost __attribute__((section(".tohost")));

enum { TILE_SKY, TILE_WALL, TILE_BALL = 4 }; /* 球占 4~7 */
enum { PAL_BG, PAL_BALL, PAL_BALL2 };
#define BALLS 8

static uint32_t solid(uint32_t color)
{
    return color * 0x11111111u;
}

/* 16x16 的球拆成 4 个 8x8 图块: 外圈色 1, 里圈色 2, 其余透明 */
static void load_ball(void)
{
    for (uint32_t t = 0; t < 4; t++) {
        uint32_t rows[8];
        for (uint32_t r = 0; r < 8; r++) {
            rows[r] = 0;
            for (uint32_t c = 0; c < 8; c++) {
                int32_t dx = (int32_t)((t & 1) * 16 + c * 2) - 15, dy = (int32_t)((t >> 1) * 16 + r * 2) - 15;
                int32_t d = dx * dx + dy * dy;
                uint32_t color = d < 100 ? 2 : d < 225 ? 1 : 0;
                rows[r] |= color << (c * 4);
            }
        }
        video_tile(TILE_BALL + t, rows);
    }
}

int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    uart_puts(CONSOLE_UART, board_hdmi_init() ? "HDMI chip: no answer\r\n" : "HDMI chip: ok\r\n");

    video_palette(PAL_BG, 0, 0x0010 /* 深蓝 */);
    video_palette(PAL_BG, 1, 0xFFFF);
    video_palette(PAL_BALL, 1, 0xF800);
    video_palette(PAL_BALL, 2, 0xFFE0);
    video_palette(PAL_BALL2, 1, 0x07E0);
    video_palette(PAL_BALL2, 2, 0xFFFF);

    const uint32_t sky[8] = {solid(0), solid(0), solid(0), solid(0), solid(0), solid(0), solid(0), solid(0)};
    const uint32_t wall[8] = {solid(1), solid(1), solid(1), solid(1), solid(1), solid(1), solid(1), solid(1)};
    video_tile(TILE_SKY, sky);
    video_tile(TILE_WALL, wall);
    load_ball();

    /* 一圈 8 像素宽的白框 */
    for (uint32_t y = 0; y < VIDEO_MAP_H; y++)
        for (uint32_t x = 0; x < VIDEO_MAP_W; x++) {
            int edge = x == 0 || x == VIDEO_W / 8 - 1 || y == 0 || y == VIDEO_H / 8 - 1;
            video_map(x, y, edge ? TILE_WALL : TILE_SKY, PAL_BG);
        }
    for (uint32_t n = 0; n < VIDEO_SPRITE_N; n++)
        video_sprite_hide(n);
    video_sprite(0, 16, 16, TILE_BALL, PAL_BALL);

    int32_t x[BALLS], y[BALLS], dx[BALLS], dy[BALLS];
    for (int i = 0; i < BALLS; i++) {
        x[i] = 20 + i * 35;
        y[i] = 130 + (i & 3) * 20;
        dx[i] = i & 1 ? 1 : -1;
        dy[i] = i & 2 ? 1 : -1;
    }
    VIDEO->CTRL = VIDEO_CTRL_EN;
    tohost = 1;

    for (;;) {
        video_wait_frame();
        for (int i = 0; i < BALLS; i++) {
            x[i] += dx[i];
            y[i] += dy[i];
            if (x[i] <= 8 || x[i] >= VIDEO_W - 8 - 16)
                dx[i] = -dx[i];
            if (y[i] <= VIDEO_H / 2 || y[i] >= VIDEO_H - 8 - 16)
                dy[i] = -dy[i];
            video_sprite(1 + i, x[i], y[i], TILE_BALL, i & 1 ? PAL_BALL2 : PAL_BALL);
        }
    }
}
