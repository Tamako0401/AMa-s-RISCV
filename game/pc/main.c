/* 东方式弹幕的电脑版: 游戏逻辑 (core/) 和板上同一份, 这里只管窗口、输入和统计。
 *
 * 用法: build/touhou [--dump 文件.jsonl] [--port 5005] [--level n] [--shot 帧号 文件.bmp]
 *   手的输入: 另开终端跑 model/hand_send.py (MediaPipe 或自己的模型), 结果经本机 UDP 发过来; 收到第一个包自动切到手。
 *   --dump: 存下有代表性的帧 (精灵表), 给参考模型数每行要画多少。
 *   --level: 开局就额外加几级难度 (同按 L); --shot: 到第几帧截图存下并退出 (不用人看也能检查画面)。
 *   --bot: 自机自己绕圈、不会死, 用来跑统计 (配合 --level、--dump 造最密的画面)。
 * 按键: M 切换 手 / 鼠标 (鼠标左键 = bomb); R 重开; L 难度加一级, K 恢复 (造最密的画面); F 全屏; Q / Esc 退出 */
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "fixed.h"
#include "gfx_mem.h"
#include "hand_udp.h"
#include "render.h"
#include "stats.h"
#include "touhou.h"

#define FPS 60

static touhou_t game;
static hand_t hand;

static void report(const char *mode)
{
    printf("[%s] 坚持 %u 秒, 得分 %u, 被击中 %u 次, 用 bomb %u 个 | 精灵最多 %u 个, 一行最多 %u 个对象 / %u 个点\n", mode,
           game.t / FPS, game.score, game.hits, game.bombs_used, stats.max_sprites, stats.max_line_objects,
           stats.max_line_pixels);
    fflush(stdout);
}

/* 电脑上看的调试信息, 写在左侧栏下部 */
static void debug_hud(const char *mode)
{
    gfx_text(4, 34, GFX_GRAY, "INPUT");
    gfx_text(10, 34, GFX_WHITE, mode);
    gfx_text(4, 36, GFX_GRAY, "SPRITES");
    gfx_number(14, 36, GFX_WHITE, stats.sprites, 5);
    gfx_text(4, 37, GFX_GRAY, "LINE OBJ");
    gfx_number(14, 37, GFX_WHITE, stats.line_objects, 5);
    gfx_text(4, 38, GFX_GRAY, "LINE PIX");
    gfx_number(14, 38, GFX_WHITE, stats.line_pixels, 5);
    gfx_text(4, 40, GFX_GRAY, "MOVED");
    gfx_number(14, 40, GFX_WHITE, game.work.bullets_moved, 5);
    gfx_text(4, 41, GFX_GRAY, "HIT TEST");
    gfx_number(14, 41, GFX_WHITE, game.work.hit_tests, 5);
}

int main(int argc, char **argv)
{
    const char *dump = NULL, *shot = NULL;
    int port = 5005, level = 0, bot = 0;
    uint32_t shot_frame = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--dump") && i + 1 < argc)
            dump = argv[++i];
        else if (!strcmp(argv[i], "--port") && i + 1 < argc)
            port = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--level") && i + 1 < argc)
            level = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--bot"))
            bot = 1;
        else if (!strcmp(argv[i], "--shot") && i + 2 < argc) {
            shot_frame = (uint32_t)atoi(argv[++i]);
            shot = argv[++i];
        } else {
            fprintf(stderr, "用法: %s [--dump 文件.jsonl] [--port 5005] [--level n] [--shot 帧号 文件.bmp] [--bot]\n", argv[0]);
            return 1;
        }
    }

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "SDL: %s\n", SDL_GetError());
        return 1;
    }
    SDL_Window *window = SDL_CreateWindow("touhou", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, GFX_W * 2, GFX_H * 2,
                                          SDL_WINDOW_RESIZABLE);
    SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_TARGETTEXTURE);
    SDL_RenderSetLogicalSize(renderer, GFX_W * 2, GFX_H * 2); /* 窗口多大都按 1280x720 等比缩放 */
    render_init(renderer);
    if (hand_udp_open(port) != 0)
        fprintf(stderr, "UDP 端口 %d 打不开, 只能用鼠标\n", port);

    touhou_screen();
    if (dump)
        stats_open_dump(dump);
    touhou_init(&game, 1);
    game.level_bonus = (uint8_t)level;
    uint32_t frame = 0;
    hand_init(&hand, game.px, game.py);
    hand_raw_t raw = {0};
    int use_hand = 0, got_hand = 0, fullscreen = 0, click = 0, restart = 0, was_over = 0;

    uint64_t period = SDL_GetPerformanceFrequency() / FPS, next = SDL_GetPerformanceCounter();
    for (int running = 1; running;) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT)
                running = 0;
            else if (e.type == SDL_MOUSEBUTTONDOWN && e.button.button == SDL_BUTTON_LEFT)
                click = 1;
            else if (e.type == SDL_KEYDOWN)
                switch (e.key.keysym.sym) {
                case SDLK_q:
                case SDLK_ESCAPE: running = 0; break;
                case SDLK_m: use_hand = !use_hand; break;
                case SDLK_r: restart = 1; break;
                case SDLK_l: game.level_bonus++; break;
                case SDLK_k: game.level_bonus = 0; break;
                case SDLK_f:
                    fullscreen = !fullscreen;
                    SDL_SetWindowFullscreen(window, fullscreen ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0);
                    break;
                }
        }

        const uint8_t *image = NULL;
        if (hand_udp_poll(&raw, &image) && !got_hand)
            use_hand = got_hand = 1; /* 第一次收到手的结果, 切到手 */
        if (image)
            render_camera(image);
        hand_update(&hand, &raw, PLAY_W, PLAY_H);

        control_t in;
        if (use_hand) {
            touhou_control_from_hand(&hand, &in);
        } else { /* 鼠标: 窗口坐标按 1280x720 算, 缩回 640x360 再减去游戏区左边 */
            int mx, my;
            SDL_GetMouseState(&mx, &my);
            float lx, ly;
            SDL_RenderWindowToLogical(renderer, mx, my, &lx, &ly);
            in = (control_t){.has_pos = 1, .bomb = (uint8_t)click};
            int x = (int)lx / 2 - PLAY_X, y = (int)ly / 2;
            in.x = Q8(x < 0 ? 0 : x >= PLAY_W ? PLAY_W - 1 : x);
            in.y = Q8(y < 0 ? 0 : y >= PLAY_H ? PLAY_H - 1 : y);
        }
        if (bot) { /* 在下半场绕椭圆, 一直无敌 */
            in = (control_t){.has_pos = 1};
            in.x = Q8(PLAY_W / 2) + 120 * fx_cos(frame * 200) / 64;
            in.y = Q8(PLAY_H * 3 / 4) + 50 * fx_sin(frame * 330) / 64;
            game.invincible = 2; /* step 里先减 1 再判定 */
        }
        in.restart = (uint8_t)restart;
        click = restart = 0;

        touhou_step(&game, &in);
        if (game.over && !was_over)
            report(bot ? "bot" : use_hand ? "hand" : "mouse");
        was_over = game.over;
        touhou_draw(&game, &hand);
        stats_frame();
        debug_hud(use_hand ? "hand " : "mouse");
        frame++;
        int last = shot && frame == shot_frame;
        render_frame(last ? shot : NULL);
        if (last)
            running = 0;

        /* 定成 60 帧/秒; 落后太多 (被拖住了) 就不追了 */
        next += period;
        uint64_t now = SDL_GetPerformanceCounter();
        if (now < next)
            SDL_Delay((uint32_t)((next - now) * 1000 / SDL_GetPerformanceFrequency()));
        else if (now - next > period * 5)
            next = now;
    }
    if (!game.over)
        report(bot ? "bot" : use_hand ? "hand" : "mouse");
    stats_close();
    SDL_Quit();
    return 0;
}
