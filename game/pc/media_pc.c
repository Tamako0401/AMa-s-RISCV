#include <stdio.h>
#include <stdlib.h>
#include "gfx.h"
#include "bgm.h"
#include "pak.h"
#include "media_pc.h"
#include "assets.h"
static pak_t pak;
static FILE *file;
static int tried, loaded = -1;
uint16_t portrait_pixels[3][4096];
unsigned portrait_revision;
static int read_block(uint32_t lba, uint8_t data[512])
{
    return !fseek(file, (long)lba * 512, SEEK_SET) && fread(data, 1, 512, file) == 512;
}
static int open_pak(void)
{
    if (tried)
        return file != NULL;
    tried = 1;
    const char *path = getenv("AMA_PAK");
    if (path)
        file = fopen(path, "rb");
    else {
        file = fopen("game/build/AMA.PAK", "rb");
        if (!file)
            file = fopen("build/AMA.PAK", "rb");
    }
    if (!file)
        return 0;
    if (fseek(file, 0, SEEK_END))
        goto bad;
    long size = ftell(file);
    if (size < 0 || (unsigned long)size > UINT32_MAX || !pak_open(&pak, read_block, 0, (uint32_t)size))
        goto bad;
    return 1;
bad:
    fclose(file);
    file = NULL;
    return 0;
}
int portrait_size(unsigned image)
{
    return gfx_portrait_ready() && image >= 1000 && image <= 1002 ? (image == 1000 ? 64 : 32) : 0;
}
int gfx_portrait_ready(void)
{
    return loaded >= 0;
}
int gfx_portrait_load(int32_t id)
{
    if (id == loaded)
        return id >= 0;
    loaded = -1;
    pak_entry_t e;
    if (id < 0 || !open_pak() || !pak_find(&pak, PAK_PORTRAIT, (uint32_t)id, &e))
        return 0;
    uint8_t palette[256], pixels[4096];
    if (!pak_read(&pak, e.offset, palette, 256))
        return 0;
    uint32_t off = e.offset + 512;
    for (int tile = 0; tile < 3; tile++) {
        int n = tile ? 1024 : 4096;
        if (!pak_read(&pak, off, pixels, (uint32_t)n))
            return 0;
        for (int i = 0; i < n; i++) {
            int p = pixels[i];
            if (p && p < 128)
                return 0;
            portrait_pixels[tile][i] =
                p ? (uint16_t)(palette[(p - 128) * 2] | palette[(p - 128) * 2 + 1] << 8) : ASSET_TRANSPARENT;
        }
        off += (uint32_t)n;
    }
    loaded = id;
    portrait_revision++;
    return 1;
}
/* 任务 B 合并点: 换成 PAK_BGM 的 pak_find/pak_read -> PCM 模型。
 * 当前 PC 只预览立绘, 音乐静音; 不创建另一个 SDL 设备。 */
void bgm_play(uint32_t id)
{
    (void)id;
}
void bgm_stop(void)
{
}
void bgm_frame(void)
{
}
