#ifndef GAME_MIX_H
#define GAME_MIX_H
#include <stdint.h>
#define MIX_POOL_BYTES (12 * 1024)
#define MIX_TARGET 800 /* 16 kHz 的50 ms, 约3个游戏帧 */
/* 声音停后再补几帧静音才关 PCM: 队列里最后的声音 (至多3帧) 放完, 关时只清掉静音, 不等队列放空 (放空就欠载) */
#define MIX_QUIET_FRAMES 5
typedef int (*mix_read_fn)(uint32_t offset, void *data, uint32_t n);
void mix_init(void);
/* 开机预留, 读成功后才提交; 失败不消耗池空间。name 最多23字节。 */
int8_t *mix_reserve(unsigned n);
int mix_commit(const char *name, unsigned n);
int mix_play(const char *name, unsigned priority, unsigned volume);
void mix_stop_sfx(void);
void mix_music(mix_read_fn read, uint32_t offset, uint32_t length, uint32_t start, uint32_t end);
void mix_stop_music(void);
/* 平台接口只在主循环调用; write 必须接收给定的整字样本。 */
int mix_hw_space(void);
void mix_hw_write(const int8_t *data, int n);
void mix_hw_enable(int on);
void mix_frame(void);
#endif
