#include "pak.h"
#define INVALID 0xffffffffu
static uint32_t le16(const uint8_t *b)
{
    return b[0] | (uint32_t)b[1] << 8;
}
static uint32_t le32(const uint8_t *b)
{
    return le16(b) | le16(b + 2) << 16;
}
static int block(pak_t *p, uint32_t lba)
{
    if (p->cache_lba == lba)
        return 1;
    p->cache_lba = INVALID;
    if (!p->read(lba, p->block))
        return 0;
    p->cache_lba = lba;
    return 1;
}
int pak_read(pak_t *p, uint32_t off, void *dst, uint32_t n)
{
    uint8_t *d = dst;
    if (off > p->size || n > p->size - off)
        return 0;
    while (n) {
        uint32_t k = 512 - (off & 511);
        if (k > n)
            k = n;
        if (!block(p, p->lba + (off >> 9)))
            return 0;
        for (uint32_t i = 0; i < k; i++)
            *d++ = p->block[(off & 511) + i];
        n -= k;
        off += k;
    }
    return 1;
}
int pak_open(pak_t *p, pak_block_fn read, uint32_t lba, uint32_t bytes)
{
    p->read = read;
    p->cache_lba = INVALID;
    p->lba = lba;
    p->size = bytes;
    p->count = 0;
    if (bytes < 512 || !block(p, lba))
        return 0;
    const uint8_t *b = p->block;
    static const char magic[8] = "AMAPAK1";
    for (int i = 0; i < 8; i++)
        if (b[i] != (uint8_t)magic[i])
            return 0;
    uint32_t count = le32(b + 12), size = le32(b + 16);
    if (le32(b + 8) != 1 || count > 64 || size > bytes || size < 512 + count * 64 || (size & 511))
        return 0;
    p->size = size;
    p->count = count;
    return 1;
}
int pak_find(pak_t *p, uint32_t type, uint32_t id, pak_entry_t *e)
{
    uint8_t b[64];
    for (uint32_t i = 0; i < p->count; i++) {
        if (!pak_read(p, 512 + i * 64, b, 64))
            return 0;
        if (le32(b + 24) != type || le32(b + 28) != id)
            continue;
        e->offset = le32(b + 32);
        e->length = le32(b + 36);
        e->loop_start = le32(b + 40);
        e->loop_end = le32(b + 44);
        uint32_t first = (512 + p->count * 64 + 511) & ~511u;
        if (e->offset < first || (e->offset & 511) || e->offset > p->size || e->length > p->size - e->offset)
            return 0;
        if (type == PAK_PORTRAIT)
            return e->length == PAK_PORTRAIT_BYTES;
        if (type == PAK_SFX)
            return e->length && e->length <= 16000 && !(e->length & 3) && !e->loop_start && !e->loop_end;
        return type == PAK_BGM && e->length && !(e->length & 3) && !(e->loop_start & 3) && !(e->loop_end & 3) &&
               (!e->loop_end || (e->loop_start < e->loop_end && e->loop_end <= e->length));
    }
    return 0;
}
static uint32_t next(pak_t *p, uint32_t fat, uint32_t c)
{
    if (!block(p, fat + (c >> 7)))
        return 0;
    return le32(p->block + (c & 127) * 4) & 0x0fffffff;
}
int pak_mount(pak_t *p, pak_block_fn read)
{
    p->read = read;
    p->cache_lba = INVALID;
    p->count = p->size = 0;
    if (!block(p, 0))
        return 0;
    uint32_t vol = 0;
    if (le16(p->block + 11) != 512) {
        if (le16(p->block + 510) != 0xaa55)
            return 0;
        vol = le32(p->block + 454);
        if (!vol || !block(p, vol))
            return 0;
    }
    uint8_t *b = p->block;
    uint32_t spc = b[13], reserved = le16(b + 14), fats = b[16], fs = le32(b + 36), total = le32(b + 32);
    uint32_t root = le32(b + 44), active = le16(b + 40);
    if (le16(b + 510) != 0xaa55 || le16(b + 11) != 512 || !spc || spc > 128 || (spc & (spc - 1)) || !reserved ||
        !fats || fats > 2 || !fs || le16(b + 17) || le16(b + 22) || le16(b + 42))
        return 0;
    if (fs > (0xffffffffu - reserved) / fats)
        return 0;
    uint32_t overhead = reserved + fats * fs;
    if (total <= overhead || vol > 0xffffffffu - total)
        return 0;
    uint32_t clusters = (total - overhead) / spc;
    if (clusters < 65525 || clusters > 0x0fffffed || fs < (clusters + 129) / 128)
        return 0;
    uint32_t fat = vol + reserved, data = vol + overhead;
    if (active & 128) {
        if ((active & 15) >= fats)
            return 0;
        fat += (active & 15) * fs;
    }
    for (int depth = 0; depth < 128; depth++) {
        if (root < 2 || root - 2 >= clusters)
            return 0;
        for (uint32_t s = 0; s < spc; s++) {
            if (!block(p, data + (root - 2) * spc + s))
                return 0;
            for (int i = 0; i < 512; i += 32) {
                b = p->block + i;
                if (!b[0])
                    return 0;
                if (b[0] == 0xe5 || (b[11] & 0x18) || b[11] == 0x0f)
                    continue;
                static const char name[] = "AMA     PAK";
                int j = 0;
                while (j < 11 && b[j] == (uint8_t)name[j])
                    j++;
                if (j != 11)
                    continue;
                uint32_t c = le16(b + 26) | le16(b + 20) << 16, bytes = le32(b + 28);
                uint32_t needed = ((bytes - 1) / 512) / spc + 1;
                if (!bytes || c < 2 || c - 2 >= clusters || needed > clusters - (c - 2))
                    return 0;
                uint32_t lba = data + (c - 2) * spc;
                for (uint32_t k = 0; k < needed; k++) {
                    uint32_t n = next(p, fat, c + k);
                    if (k + 1 < needed ? n != c + k + 1 : n < 0x0ffffff8)
                        return 0;
                }
                return pak_open(p, read, lba, bytes);
            }
        }
        root = next(p, fat, root);
    }
    return 0;
}
