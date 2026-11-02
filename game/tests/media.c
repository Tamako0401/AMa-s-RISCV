/* 使用板上 media.c, SD 换内存块设备, PCM 换2048样本FIFO, 显示 MMIO mmap。 */
#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include "../board/media.c"
static uint8_t *bytes;
static uint32_t size, accesses;
static int io_fail, enabled, level;
static int8_t fifo[2048], output[65536];
static int out_n;
int sd_init(void)
{
    return 2;
}
int sd_read_block(uint32_t lba, uint8_t data[512])
{
    accesses++;
    if (io_fail || lba >= size / 512)
        return 0;
    memcpy(data, bytes + lba * 512, 512);
    return 1;
}
void board_audio_init(void)
{
}
void audio_pcm_enable(int en, int div)
{
    assert(div == 3);
    enabled = en;
    if (!en)
        level = 0;
}
int audio_pcm_space(void)
{
    return 2048 - level;
}
int audio_pcm_write(const int8_t *s, int n)
{
    assert(enabled && n >= 0 && n % 4 == 0 && n <= 2048 - level);
    memcpy(fifo + level, s, (size_t)n);
    level += n;
    return n;
}
void audio_pcm_volume(uint32_t v)
{
    assert(v <= 255);
}
static void drain(int n)
{
    if (n > level)
        n = level;
    assert(out_n + n <= (int)sizeof output);
    memcpy(output + out_n, fifo, (size_t)n);
    memmove(fifo, fifo + n, (size_t)(level - n));
    out_n += n;
    level -= n;
}
static void put32(uint32_t off, uint32_t v)
{
    memcpy(bytes + off, &v, 4);
}
int main(int argc, char **argv)
{
    assert(argc == 2);
    FILE *f = fopen(argv[1], "rb");
    assert(f);
    fseek(f, 0, SEEK_END);
    size = (uint32_t)ftell(f);
    rewind(f);
    bytes = malloc(size);
    assert(bytes);
    assert(fread(bytes, 1, size, f) == size);
    fclose(f);
    void *display =
        mmap((void *)0x30000000, 0x50000, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    assert(display != MAP_FAILED);
    assert(pak_open(&pak, sd_read_block, 0, size));
    available = 1;
    assert(gfx_portrait_load(0));
    pak_entry_t e;
    assert(pak_find(&pak, PAK_PORTRAIT, 0, &e));
    assert(!memcmp((uint8_t *)display + 0x40000 + 57344, bytes + e.offset + 512, 6144));
    uint32_t before = accesses;
    assert(gfx_portrait_load(0) && accesses == before); /* 同一张不重写/重读 */
    assert(!gfx_portrait_load(999) && !gfx_portrait_ready());
    assert(gfx_portrait_load(0));
    assert(pak_find(&pak, PAK_BGM, 0, &e));
    bgm_play(0);
    for (int i = 0; playing && i < 1000; i++) {
        drain(267);
        bgm_frame();
    }
    assert(!playing && !enabled && out_n == (int)e.length);
    assert(!memcmp(output, bytes + e.offset, e.length));
    out_n = 0;
    /* 4对齐、非扇区对齐循环点; 首段[0,2000), 之后[1000,2000)。 */
    put32(512 + 64 + 40, 1000);
    put32(512 + 64 + 44, 2000);
    pak.cache_lba = 0xffffffff;
    bgm_play(0);
    while (out_n < 5000) {
        drain(267);
        bgm_frame();
    }
    for (int i = 0; i < out_n; i++)
        assert((uint8_t)output[i] == bytes[e.offset + (i < 2000 ? i : 1000 + (i - 2000) % 1000)]);
    bgm_stop();
    assert(!playing && !enabled && !level);
    bgm_play(99);
    assert(!playing && !enabled);
    bgm_play(0);
    drain(512);
    io_fail = 1;
    pak.cache_lba = 0xffffffff;
    bgm_frame();
    assert(!playing && !enabled);
    available = 0;
    assert(!gfx_portrait_load(99));
    bgm_play(0);
    assert(!enabled);
    puts("board media: portrait upload/cache/missing, PCM exact bytes/tail/loop/FIFO/error passed");
    free(bytes);
    munmap(display, 0x50000);
    return 0;
}
