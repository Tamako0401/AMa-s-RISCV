#include "sound.h"
#include "mix.h"

/* 每步: 起止 Hz、起止音量、帧数、占空比 (噪声为短周期开关)、颤音深度 Hz。
 * 每个音效最多两步, frames=0 是结尾; type=0 方波, 1 噪声。 */
typedef struct {
    uint16_t hz0, hz1;
    uint8_t vol0, vol1, frames, duty, vibrato;
} step_t;
typedef struct {
    const char *wav;
    uint8_t volume, type, priority;
    step_t step[2];
} effect_t;
static const effect_t effects[SFX_COUNT] = {
    [SFX_SHOT] = {"shot", 128, 0, 1, {{900, 700, 12, 0, 3, 64, 0}}},
    [SFX_GRAZE] = {"graze", 128, 0, 2, {{1400, 1900, 28, 0, 5, 32, 12}}},
    [SFX_ENEMY_HIT] = {"enemy_hit", 128, 1, 2, {{6500, 3000, 25, 0, 3, 0, 0}}},
    [SFX_ENEMY_EXPLODE] = {"enemy_explode", 128, 1, 4, {{10000, 800, 100, 0, 16, 0, 0}}},
    [SFX_PLAYER_HIT] = {"player_hit", 128, 1, 6, {{12000, 4000, 150, 70, 8, 0, 0}, {4000, 500, 70, 0, 20, 0, 0}}},
    [SFX_BOMB] = {"bomb", 128, 1, 7, {{15000, 7000, 160, 100, 12, 0, 0}, {7000, 300, 100, 0, 30, 0, 0}}},
    [SFX_ITEM] = {"item", 128, 0, 4, {{660, 990, 65, 50, 6, 128, 0}, {1320, 1600, 50, 0, 9, 128, 6}}},
    [SFX_START] = {"start", 128, 0, 5, {{440, 880, 65, 65, 8, 128, 0}, {1320, 1320, 65, 0, 10, 128, 4}}},
    [SFX_END] = {"end", 128, 0, 6, {{660, 330, 70, 50, 12, 128, 0}, {330, 110, 50, 0, 18, 128, 8}}},
    [SFX_SLASH] = {"slash", 128, 1, 1, {{11000, 6000, 24, 0, 4, 0, 0}}},
    [SFX_CUT] = {"cut", 128, 0, 3, {{700, 1200, 50, 0, 5, 64, 0}}},
    [SFX_FRUIT_BOMB] = {"fruit_bomb", 128, 1, 7, {{13000, 600, 150, 0, 24, 0, 0}}},
    [SFX_MISS] = {"miss", 128, 0, 3, {{330, 160, 45, 0, 10, 128, 4}}},
    [SFX_MENU_MOVE] = {"menu_move", 128, 0, 2, {{600, 600, 35, 0, 3, 64, 0}}},
    [SFX_MENU_OK] = {"menu_ok", 128, 0, 4, {{800, 800, 50, 40, 4, 128, 0}, {1200, 1200, 40, 0, 6, 128, 0}}},
};
static struct {
    uint8_t active, id, step, frame;
} voices[4];
void sound_reset(void)
{
    mix_stop_sfx();
    for (unsigned ch = 0; ch < 4; ch++) {
        voices[ch].active = 0;
        sound_hw_off(ch);
    }
}
void sound_play(sfx_id id)
{
    if ((unsigned)id >= SFX_COUNT)
        return;
    const effect_t *e = &effects[id];
    if (mix_play(e->wav, e->priority, e->volume))
        return;
    unsigned first = e->type ? 3 : 0, end = e->type ? 4 : 3, best = first;
    for (unsigned ch = first; ch < end; ch++) {
        if (!voices[ch].active) {
            best = ch;
            break;
        }
        if (effects[voices[ch].id].priority < effects[voices[best].id].priority)
            best = ch;
    }
    if (voices[best].active && effects[voices[best].id].priority >= e->priority)
        return;
    voices[best].active = 1;
    voices[best].id = (uint8_t)id;
    voices[best].step = voices[best].frame = 0;
}
static int lerp(int a, int b, unsigned frame, unsigned frames)
{
    return a + (b - a) * (int)frame / (int)(frames > 1 ? frames - 1 : 1);
}
void sound_frame(void)
{
    for (unsigned ch = 0; ch < 4; ch++) {
        if (!voices[ch].active)
            continue;
        if (voices[ch].step == 2) {
            voices[ch].active = 0;
            sound_hw_off(ch);
            continue;
        }
        const effect_t *e = &effects[voices[ch].id];
        const step_t *s = &e->step[voices[ch].step];
        unsigned t = voices[ch].frame;
        int hz = lerp(s->hz0, s->hz1, t, s->frames);
        hz += (t & 2 ? -1 : 1) * s->vibrato;
        unsigned freq = ((unsigned)hz * 65536u + 24000u) / 48000u;
        unsigned vol = (unsigned)lerp(s->vol0, s->vol1, t, s->frames);
        if (ch == 3)
            sound_hw_noise(freq, vol, s->duty);
        else
            sound_hw_tone(ch, freq, vol, s->duty);
        if (++voices[ch].frame == s->frames) {
            voices[ch].frame = 0;
            if (++voices[ch].step == 2 || !e->step[voices[ch].step].frames) {
                /* 末帧保留一个游戏帧, 下次 sound_frame 才关。 */
                voices[ch].step = 2;
            }
        }
    }
}
