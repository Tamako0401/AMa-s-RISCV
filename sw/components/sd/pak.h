#ifndef AMA_PAK_H
#define AMA_PAK_H
#include <stdint.h>
#define PAK_PORTRAIT 1
#define PAK_BGM 2
#define PAK_SFX 3
#define PAK_PORTRAIT_IMAGE 1000
#define PAK_PORTRAIT_BASE 57344
#define PAK_PORTRAIT_BYTES 6656 /* 512 字节调色板区 + 64x64 + 两个32x32 */
typedef int (*pak_block_fn)(uint32_t lba, uint8_t data[512]);
typedef struct {
    pak_block_fn read;
    uint32_t lba, size, count, cache_lba;
    uint8_t block[512];
} pak_t;
typedef struct {
    uint32_t offset, length, loop_start, loop_end;
} pak_entry_t;
/* FAT32 (512 字节扇区, MBR 第一分区或裸卷), 根目录 AMA.PAK; 挂载检查连续性。 */
int pak_mount(pak_t *p, pak_block_fn read);
/* PC 直接 PAK 的块设备也使用同一解析器; bytes 是文件长度。 */
int pak_open(pak_t *p, pak_block_fn read, uint32_t lba, uint32_t bytes);
int pak_read(pak_t *p, uint32_t offset, void *data, uint32_t bytes);
int pak_find(pak_t *p, uint32_t type, uint32_t id, pak_entry_t *entry);
#endif
