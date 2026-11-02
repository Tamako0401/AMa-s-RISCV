/* 电脑后端的主循环, 两个游戏共用。游戏逻辑 (core/) 和板上同一份, 这里只管窗口、输入和统计。
 *
 * 用法: build/<游戏> [--dump 文件.jsonl] [--port 5005] [--level n] [--shot 帧号 文件.bmp] [--bot]
 *   手的输入: 另开终端跑 model/hand_send.py (MediaPipe 或自己的模型), 结果经本机 UDP 发过来; 收到第一个包自动切到手。
 *   --dump: 存下有代表性的帧 (精灵表), 给参考模型数每行要画多少。
 *   --level: 开局就额外加几级难度 (同按 L); --shot: 到第几帧截图存下并退出 (不用人看也能检查画面)。
 *   --bot: 不看输入, 游戏自己动、不会死, 用来跑统计 (配合 --level、--dump 造最密的画面)。
 * 按键: M 切换 手 / 鼠标; R 重开; L 难度加一级, K 恢复; F 全屏; Q / Esc 退出 */
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "app.h"
#include "audio_sdl.h"
#include "sound.h"
#include "fixed.h"
#include "gfx_mem.h"
#include "hand_udp.h"
#include "render.h"
#include "stats.h"

#define FPS 60

static void report(const app_game_t *game, const char *mode)
{
    printf("[%s] ", mode);
    game->report();
    printf(" | 精灵最多 %u 个, 一行最多 %u 个对象 / %u 个点\n", stats.max_sprites, stats.max_line_objects,
           stats.max_line_pixels);
    fflush(stdout);
}

/* 电脑上看的调试信息, 写在左下 */
static void debug_hud(const app_game_t *game, const char *mode)
{
    gfx_text(4, 34, GFX_GRAY, "INPUT");
    gfx_text(10, 34, GFX_WHITE, mode);
    gfx_text(4, 36, GFX_GRAY, "SPRITES");
    gfx_number(14, 36, GFX_WHITE, stats.sprites, 5);
    gfx_text(4, 37, GFX_GRAY, "LINE OBJ");
    gfx_number(14, 37, GFX_WHITE, stats.line_objects, 5);
    gfx_text(4, 38, GFX_GRAY, "LINE PIX");
    gfx_number(14, 38, GFX_WHITE, stats.line_pixels, 5);
    if (game->debug)
        game->debug();
}

int app_main(const app_game_t *game, int argc, char **argv)
{
    const char *dump = NULL, *shot = NULL;
    int port = 5005, level = 0, bot = 0, mute = 0;
    uint32_t shot_frame = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--dump") && i + 1 < argc)
            dump = argv[++i];
        else if (!strcmp(argv[i], "--port") && i + 1 < argc)
            port = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--level") && i + 1 < argc)
            level = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--mute"))
            mute = 1;
        else if (!strcmp(argv[i], "--bot"))
            bot = 1;
        else if (!strcmp(argv[i], "--shot") && i + 2 < argc) {
            shot_frame = (uint32_t)atoi(argv[++i]);
            shot = argv[++i];
        } else {
            fprintf(stderr,
                    "用法: %s [--dump 文件.jsonl] [--port 5005] [--level n] [--shot 帧号 文件.bmp] [--bot] [--mute]\n",
                    argv[0]);
            return 1;
        }
    }

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "SDL: %s\n", SDL_GetError());
        return 1;
    }
    SDL_Window *window = SDL_CreateWindow(game->name, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, GFX_W * 2,
                                          GFX_H * 2, SDL_WINDOW_RESIZABLE);
    SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_TARGETTEXTURE);
    SDL_RenderSetLogicalSize(renderer, GFX_W * 2, GFX_H * 2); /* 窗口多大都按 1280x720 等比缩放 */
    render_init(renderer);
    if (hand_udp_open(port) != 0)
        fprintf(stderr, "UDP 端口 %d 打不开, 只能用鼠标\n", port);

    audio_sdl_init(mute);
    sound_reset();
    game->start(level);
    if (dump)
        stats_open_dump(dump);
    hand_t hand;
    hand_init(&hand, Q8(game->play_w / 2), Q8(game->play_h * 4 / 5));
    hand_raw_t raw = {0};
    app_input_t in = {0};
    int use_hand = 0, got_hand = 0, fullscreen = 0, was_over = 0;
    const char *mode = bot ? "bot" : "mouse";

    uint64_t period = SDL_GetPerformanceFrequency() / FPS, next = SDL_GetPerformanceCounter();
    for (int running = 1; running;) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT)
                running = 0;
            else if (e.type == SDL_MOUSEBUTTONDOWN && e.button.button == SDL_BUTTON_LEFT)
                in.click = 1;
            else if (e.type == SDL_KEYDOWN)
                switch (e.key.keysym.sym) {
                case SDLK_q:
                case SDLK_ESCAPE:
                    running = 0;
                    break;
                case SDLK_m:
                    use_hand = !use_hand;
                    break;
                case SDLK_r:
                    in.restart = 1;
                    break;
                case SDLK_l:
                    game->level(1);
                    break;
                case SDLK_k:
                    game->level(0);
                    break;
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
        hand_update(&hand, &raw, game->play_w, game->play_h);

        /* 鼠标: 窗口坐标按 1280x720 算, 缩回 640x360 再减去游戏区左边 */
        int mx, my;
        float lx, ly;
        SDL_GetMouseState(&mx, &my);
        SDL_RenderWindowToLogical(renderer, mx, my, &lx, &ly);
        int x = (int)lx / 2 - game->play_x, y = (int)ly / 2;
        in.x = Q8(x < 0 ? 0 : x >= game->play_w ? game->play_w - 1 : x);
        in.y = Q8(y < 0 ? 0 : y >= game->play_h ? game->play_h - 1 : y);

        if (!bot)
            mode = use_hand ? "hand" : "mouse";
        game->frame(&hand, &in, use_hand, bot);
        sound_frame();
        if (game->over() && !was_over)
            report(game, mode);
        was_over = game->over();
        stats_frame();
        debug_hud(game, mode);
        in.frame++;
        in.click = in.restart = 0;
        int last = shot && in.frame == shot_frame;
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
    if (!game->over())
        report(game, mode);
    stats_close();
    audio_sdl_close();
    SDL_Quit();
    return 0;
}
