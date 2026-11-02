#ifndef GAME_BGM_H
#define GAME_BGM_H
#include <stdint.h>
void bgm_play(uint32_t id); /* 切曲时清 FIFO; 找不到就静音。循环点在 PAK 目录里。 */
void bgm_stop(void);
void bgm_frame(void); /* 每帧调用, 暂停菜单期间也调用 */
#endif
