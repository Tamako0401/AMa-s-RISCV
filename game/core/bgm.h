#ifndef GAME_BGM_H
#define GAME_BGM_H
#include <stdint.h>
void bgm_play(uint32_t id); /* 替换音乐源, FIFO 混音尾巴继续; 找不到就停音乐。 */
void bgm_stop(void);
void bgm_frame(void); /* 每帧调用, 暂停菜单期间也调用 */
#endif
