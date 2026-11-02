#include "media.h"
#include "bgm.h"
#include "gfx.h"
#include "sd.h"
#include "pak.h"
#include "board_audio.h"
static pak_t pak;
static pak_entry_t music;
static uint32_t position;
static int available, playing, portrait = -1;

int media_init(void)
{
    portrait = -1;
    board_audio_init();
    bgm_stop();
    available = sd_init() && pak_mount(&pak, sd_read_block);
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
void bgm_stop(void)
{
    playing = 0;
    audio_pcm_enable(0, 3);
}
void bgm_play(uint32_t id)
{
    bgm_stop();
    if (!available || !pak_find(&pak, PAK_BGM, id, &music))
        return;
    position = 0;
    playing = 1;
    audio_pcm_volume(96);
    audio_pcm_enable(1, 3);
    bgm_frame();
}
void bgm_frame(void)
{
    if (playing == 2) {
        if (audio_pcm_space() == 2048)
            bgm_stop();
        return;
    }
    int8_t buf[512];
    /* 最多4块/帧; 无循环点放完一次。有循环点时 [start,end) 重复。 */
    for (int blocks = 0; playing && blocks < 4; blocks++) {
        uint32_t end = music.loop_end ? music.loop_end : music.length;
        if (position == end) {
            if (!music.loop_end) {
                playing = 2;
                break;
            } /* FIFO 自然排空, 不截掉尾音 */
            position = music.loop_start;
        }
        uint32_t n = end - position;
        uint32_t space = (uint32_t)audio_pcm_space() & ~3u;
        if (n > 512)
            n = 512;
        if (n > space)
            n = space;
        if (!n)
            break;
        if (!pak_read(&pak, music.offset + position, buf, n)) {
            bgm_stop();
            break;
        }
        position += (uint32_t)audio_pcm_write(buf, (int)n);
    }
}
