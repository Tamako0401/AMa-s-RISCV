/* CPU RTL 上对比 -O2/-Os: 固定320弹、8帧, 包含 step/draw/板上精灵表提交。
 * 显示 MMIO 只确认写请求, 不等待视频时序; 无 SD/手势网络/HDMI 轮询。 */
#include "touhou.h"
#include "gfx_hw.h"
#include "bgm.h"
static touhou_t game;
const uint8_t display_pack[] = {3, 0xff, 0xff, 0xff, 0xff}; /* 只有结尾标记 */
const uint8_t display_font[2048] = {0};
int gfx_portrait_load(int32_t id)
{
    (void)id;
    return 0;
}
int gfx_portrait_ready(void)
{
    return 0;
}
void bgm_play(uint32_t id)
{
    (void)id;
}
static uint32_t cycles(void)
{
    uint32_t n;
    __asm__ volatile("rdcycle %0" : "=r"(n));
    return n;
}
int main(void)
{
    touhou_init(&game, 1);
    game.t = 1800;
    game.next_fire = game.next_shot = 2000;
    game.invincible = 100;
    game.bullet_n = 320;
    for (int i = 0; i < 320; i++)
        game.bullets[i] =
            (bullet_t){.x = (i % 20 + 1) * 15 * 256, .y = (i / 20 + 1) * 16 * 256, .vy = 128, .kind = i % 3};
    control_t in = {.has_pos = 1, .x = 160 * 256, .y = 320 * 256};
    for (int f = 0; f < 8; f++) {
        uint32_t start = cycles();
        touhou_step(&game, &in);
        touhou_draw(&game, 0);
        gfx_hw_present();
        *(volatile uint32_t *)0x20000000 = cycles() - start;
    }
    return 1;
}
