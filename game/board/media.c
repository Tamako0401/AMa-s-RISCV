#include "media.h"
#include "bgm.h"
#include "gfx.h"
#include "sd.h"
#include "pak.h"
#include "board_audio.h"
#include "../media_audio.h"
#include "mix.h"
static pak_t pak;
static int available, portrait = -1;

int media_init(void)
{
    portrait = -1;
    board_audio_init();
    available = sd_init() && pak_mount(&pak, sd_read_block);
    media_audio_init(available ? &pak : 0, media_sfx_skip);
    return available;
}
int gfx_portrait_ready(void)
{
    return portrait >= 0;
}
int gfx_portrait_load(int32_t id)
{
    if (portrait == id)
        return id >= 0;
    portrait = -1;
    pak_entry_t e;
    if (id < 0 || !available || !pak_find(&pak, PAK_PORTRAIT, (uint32_t)id, &e))
        return 0;
    uint32_t buf[128];
    if (!pak_read(&pak, e.offset, buf, 512))
        return 0;
    volatile uint32_t *display = (volatile uint32_t *)0x30000000;
    for (uint32_t i = 0; i < 128; i++)
        display[0x1000 / 4 + 128 + i] = (buf[i / 2] >> ((i & 1) * 16)) & 65535;
    for (uint32_t k = 0; k < 6144; k += 512) {
        if (!pak_read(&pak, e.offset + 512 + k, buf, 512))
            return 0;
        for (uint32_t i = 0; i < 128; i++)
            display[(0x40000 + PAK_PORTRAIT_BASE + k) / 4 + i] = buf[i];
    }
    display[0x2000 / 4 + 1000] = (4u << 13) | (PAK_PORTRAIT_BASE / 8);
    display[0x2000 / 4 + 1001] = (3u << 13) | ((PAK_PORTRAIT_BASE + 4096) / 8);
    display[0x2000 / 4 + 1002] = (3u << 13) | ((PAK_PORTRAIT_BASE + 5120) / 8);
    portrait = id;
    return 1;
}
void mix_hw_enable(int on)
{
    audio_pcm_enable(on, 3);
    audio_pcm_volume(96);
}
int mix_hw_space(void)
{
    return audio_pcm_space();
}
void mix_hw_write(const int8_t *data, int n)
{
    (void)audio_pcm_write(data, n);
}
