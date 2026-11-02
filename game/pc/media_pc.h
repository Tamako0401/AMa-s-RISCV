#ifndef PC_MEDIA_H
#define PC_MEDIA_H
#include <stdint.h>
/* SDL 立绘/音乐/音效与板上使用同一 PAK。 */
extern uint16_t portrait_pixels[3][4096];
extern unsigned portrait_revision;
int portrait_size(unsigned image);
void media_pc_init(void);
#endif
