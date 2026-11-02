/* 音效只占方波 0~2 / 噪声 3; PCM 永远留给音乐。 */
#ifndef GAME_SOUND_H
#define GAME_SOUND_H
#include <stdint.h>
typedef enum {
    SFX_SHOT,
    SFX_GRAZE,
    SFX_ENEMY_HIT,
    SFX_ENEMY_EXPLODE,
    SFX_PLAYER_HIT,
    SFX_BOMB,
    SFX_ITEM,
    SFX_START,
    SFX_END,
    SFX_SLASH,
    SFX_CUT,
    SFX_FRUIT_BOMB,
    SFX_MISS,
    SFX_MENU_MOVE,
    SFX_MENU_OK,
    SFX_COUNT
} sfx_id;
void sound_play(sfx_id id);
void sound_frame(void);
void sound_reset(void);
/* 平台实现: f 是 16 位相位增量, 不是 Hz; v 0~255, duty 0~255。 */
void sound_hw_tone(unsigned ch, unsigned f, unsigned v, unsigned duty);
void sound_hw_noise(unsigned f, unsigned v, unsigned short_mode);
void sound_hw_off(unsigned ch);
#endif
