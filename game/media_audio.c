#include "media_audio.h"
#include "mix.h"
#include "bgm.h"
static pak_t *source;
static uint32_t le32(const uint8_t *b)
{
    return b[0] | (uint32_t)b[1] << 8 | (uint32_t)b[2] << 16 | (uint32_t)b[3] << 24;
}
static int read_music(uint32_t off, void *data, uint32_t n)
{
    return source && pak_read(source, off, data, n);
}
void media_audio_init(pak_t *pak, void (*skip)(const char *))
{
    mix_init();
    source = pak;
    if (!pak)
        return;
    for (uint32_t i = 0; i < pak->count; i++) {
        uint8_t b[32];
        pak_entry_t e;
        if (!pak_read(pak, 512 + i * 64, b, sizeof b))
            break;
        if (le32(b + 24) != PAK_SFX)
            continue;
        if (b[23]) { /* PAK 名字必须零结尾, 不截断成另一个音效名。 */
            b[23] = 0;
            if (skip)
                skip((const char *)b);
            continue;
        }
        int8_t *dst = 0;
        if (pak_find(pak, PAK_SFX, le32(b + 28), &e))
            dst = mix_reserve(e.length);
        if (!dst || !pak_read(pak, e.offset, dst, e.length) || !mix_commit((const char *)b, e.length)) {
            if (skip)
                skip((const char *)b);
        }
    }
}
void bgm_stop(void)
{
    /* 只停音乐源; FIFO 的混音尾巴和正在播放的音效继续。 */
    mix_stop_music();
}
void bgm_play(uint32_t id)
{
    pak_entry_t e;
    bgm_stop();
    if (source && pak_find(source, PAK_BGM, id, &e))
        mix_music(read_music, e.offset, e.length, e.loop_start, e.loop_end);
}
void bgm_frame(void)
{
    mix_frame();
}
