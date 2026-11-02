#include "sound.h"
#include "audio.h"
void sound_hw_tone(unsigned ch, unsigned f, unsigned v, unsigned duty)
{
    audio_tone(ch, f, v, duty);
}
void sound_hw_noise(unsigned f, unsigned v, unsigned short_mode)
{
    audio_noise(f, v, short_mode, 0);
}
void sound_hw_off(unsigned ch)
{
    audio_off(ch);
}
