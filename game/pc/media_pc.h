#ifndef PC_MEDIA_H
#define PC_MEDIA_H
#include <stdint.h>
/* SDL 立绘与板上使用同一 PAK 的 RGB565 调色板/图案。任务 B 可在 bgm_* 接 PCM 模型。 */
extern uint16_t portrait_pixels[3][4096];
extern unsigned portrait_revision;
int portrait_size(unsigned image);
#endif
