/* 电脑版声音外设: 与 sw/drivers/audio.h 同名、同单位。 */
#ifndef AUDIO_SDL_H
#define AUDIO_SDL_H
#include <stdint.h>
#define AUDIO_RATE 48000
#define AUDIO_SQUARE0 0
#define AUDIO_SQUARE1 1
#define AUDIO_SQUARE2 2
#define AUDIO_NOISE 3
#define AUDIO_VOL_MAX 255
#define AUDIO_HZ(hz) ((uint32_t)(((uint32_t)(hz) * 65536UL + AUDIO_RATE / 2) / AUDIO_RATE))
#define AUDIO_MS(ms) ((uint32_t)(ms) * 48)
#define AUDIO_DUTY(percent) ((uint32_t)(percent) * 256 / 100)
int audio_sdl_init(int mute);
void audio_sdl_close(void);
/* 无设备也能用的确定性测试入口; render 返回 I2S 左/右共同的样本。 */
void audio_sdl_reset(void);
void audio_sdl_render(int16_t *out, int n);
void audio_reg_write(uint32_t offset, uint32_t value);
uint32_t audio_reg_read(uint32_t offset);
void audio_enable(int on);
void audio_tone(uint32_t ch, uint32_t freq, uint32_t vol, uint32_t duty);
void audio_beep(uint32_t ch, uint32_t freq, uint32_t vol, uint32_t len);
void audio_noise(uint32_t rate, uint32_t vol, int short_mode, uint32_t len);
void audio_volume(uint32_t ch, uint32_t vol);
void audio_off(uint32_t ch);
int audio_busy(uint32_t ch);
void audio_pcm_enable(int en, int div);
int audio_pcm_space(void);
int audio_pcm_write(const int8_t *s, int n);
void audio_pcm_volume(uint32_t v);
#endif
