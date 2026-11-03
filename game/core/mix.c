#include "mix.h"
static int8_t pool[MIX_POOL_BYTES];
static struct {
    char name[24];
    uint16_t offset, length;
} clips[64];
static unsigned used, count;
static struct {
    uint16_t pos, end;
    uint8_t clip, priority, volume;
} voices[4];
static mix_read_fn music_read;
static uint32_t music_offset, music_pos, music_length, loop_start, loop_end;
static int enabled, quiet;
static int same(const char *a, const char *b)
{
    for (unsigned i = 0; i < 24; i++) {
        if (a[i] != b[i])
            return 0;
        if (!a[i])
            return 1;
    }
    return 0;
}
void mix_stop_sfx(void)
{
    for (unsigned i = 0; i < 4; i++)
        voices[i].pos = voices[i].end = 0;
}
void mix_stop_music(void)
{
    music_read = 0;
}
void mix_init(void)
{
    used = count = 0;
    mix_stop_sfx();
    mix_stop_music();
    enabled = 0;
    mix_hw_enable(0);
}
int8_t *mix_reserve(unsigned n)
{
    return n && n <= 16000 && n <= MIX_POOL_BYTES - used && count < 64 ? pool + used : 0;
}
int mix_commit(const char *name, unsigned n)
{
    if (!mix_reserve(n))
        return 0;
    unsigned i = 0;
    while (i < 23 && name[i]) {
        clips[count].name[i] = name[i];
        i++;
    }
    if (!i || name[i])
        return 0;
    for (unsigned j = 0; j < count; j++)
        if (same(name, clips[j].name))
            return 0;
    clips[count].name[i] = 0;
    clips[count].offset = used;
    clips[count++].length = n;
    used += n;
    return 1;
}
int mix_play(const char *name, unsigned priority, unsigned volume)
{
    unsigned clip;
    for (clip = 0; clip < count; clip++)
        if (same(name, clips[clip].name))
            break;
    if (clip == count)
        return 0; /* 只有缺素材才回退合成; 满声部时仍算已处理。 */
    unsigned best = 0;
    for (unsigned i = 0; i < 4; i++)
        if (voices[i].pos < voices[i].end && voices[i].clip == clip) {
            best = i;
            goto start; /* 同名重复触发从头放, 不叠声部 */
        }
    for (unsigned i = 0; i < 4; i++) {
        if (voices[i].pos == voices[i].end) {
            best = i;
            goto start;
        }
        if (voices[i].priority < voices[best].priority)
            best = i;
    }
    if (voices[best].pos < voices[best].end && voices[best].priority >= priority)
        return 1;
start:
    voices[best].clip = clip;
    voices[best].pos = clips[clip].offset;
    voices[best].end = clips[clip].offset + clips[clip].length;
    voices[best].priority = priority;
    voices[best].volume = volume > 128 ? 128 : volume;
    return 1;
}
void mix_music(mix_read_fn read, uint32_t offset, uint32_t length, uint32_t start, uint32_t end)
{
    music_read = read;
    music_offset = offset;
    music_length = length;
    music_pos = 0;
    loop_start = start;
    loop_end = end;
}
void mix_frame(void)
{
    int active = music_read != 0;
    for (unsigned v = 0; v < 4; v++)
        active |= voices[v].pos < voices[v].end;
    if (active)
        quiet = MIX_QUIET_FRAMES;
    else if (!enabled)
        return;
    else if (!quiet--) {
        mix_hw_enable(0);
        enabled = 0;
        return;
    }
    if (!enabled) {
        mix_hw_enable(1);
        enabled = 1;
    }
    int need = (mix_hw_space() - (2048 - MIX_TARGET)) & ~3;
    /* 每次最多补800样本, 即使硬件在写入期间取样也不追着填满。 */
    if (need > MIX_TARGET)
        need = MIX_TARGET;
    while (need > 0) {
        int8_t buf[64];
        int n = need > 64 ? 64 : need;
        for (int i = 0; i < n; i++)
            buf[i] = 0;
        int filled = 0;
        while (music_read && filled < n) {
            uint32_t end = loop_end ? loop_end : music_length;
            if (music_pos == end) {
                if (!loop_end) {
                    music_read = 0;
                    break;
                }
                music_pos = loop_start;
            }
            uint32_t k = end - music_pos;
            if (k > (unsigned)(n - filled))
                k = (unsigned)(n - filled);
            if (!music_read(music_offset + music_pos, buf + filled, k)) {
                /* 读失败丢弃本次失败片段, 已缓存音效仍继续。 */
                for (int i = filled; i < filled + (int)k; i++)
                    buf[i] = 0;
                music_read = 0;
                break;
            }
            music_pos += k;
            filled += (int)k;
        }
        for (int i = 0; i < n; i++) {
            int sum = buf[i];
            for (unsigned v = 0; v < 4; v++)
                if (voices[v].pos < voices[v].end)
                    sum += ((int)pool[voices[v].pos++] * voices[v].volume) / 128;
            buf[i] = sum > 127 ? 127 : sum < -128 ? -128 : sum;
        }
        mix_hw_write(buf, n);
        need -= n;
    }
}
