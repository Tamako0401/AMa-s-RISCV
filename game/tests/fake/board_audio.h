#ifndef FAKE_BOARD_AUDIO_H
#define FAKE_BOARD_AUDIO_H
#include <stdint.h>
void board_audio_init(void);
void audio_pcm_enable(int en, int div);
int audio_pcm_space(void);
int audio_pcm_write(const int8_t *s, int n);
void audio_pcm_volume(uint32_t v);
#endif
