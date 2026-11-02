/* 真正的PC PCM模型接共用混音器, 不需要声卡/窗口。 */
#include "audio_sdl.h"
#include "bgm.h"
#include "mix.h"
#include "sound.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static int music(uint32_t offset, void *data, uint32_t n)
{
    (void)offset;
    memset(data, 20, n);
    return 1;
}
int main(void)
{
    audio_sdl_reset();
    audio_enable(1);
    mix_init();
    sound_reset();
    memset(mix_reserve(1600), 100, 1600);
    assert(mix_commit("shot", 1600));
    mix_music(music, 0, 16000, 0, 0);
    sound_play(SFX_SHOT);
    sound_frame();
    bgm_frame();
    assert((audio_reg_read(0x58) & 65535) == MIX_TARGET);
    int16_t samples[800];
    audio_sdl_render(samples, 4);
    assert(samples[0] == 0 && samples[1] == 120 * 96);
    sound_play(SFX_GRAZE); /* 没有graze素材, 方波和PCM同时响 */
    sound_frame();
    assert(audio_reg_read(0x14) == 28);
    audio_sdl_render(samples, 800);
    int changed = 0;
    for (int i = 1; i < 800; i++)
        changed |= samples[i] != 120 * 96;
    assert(changed);
    bgm_frame();
    assert((audio_reg_read(0x58) & 65535) >= 797);
    puts("PC mix -> SDL PCM: BGM + WAV + synth, watermark passed");
}
