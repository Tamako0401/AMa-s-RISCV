#include "sound.h"
#include <assert.h>
#include <stdio.h>
static unsigned volume[4], frequency[4], calls[4];
void sound_hw_tone(unsigned ch, unsigned f, unsigned v, unsigned d)
{
    assert(ch < 3 && d <= 255);
    frequency[ch] = f;
    volume[ch] = v;
    calls[ch]++;
}
void sound_hw_noise(unsigned f, unsigned v, unsigned s)
{
    assert(s <= 1);
    frequency[3] = f;
    volume[3] = v;
    calls[3]++;
}
void sound_hw_off(unsigned ch)
{
    volume[ch] = 0;
}
int main(void)
{
    sound_reset();
    sound_play(SFX_SHOT);
    sound_frame();
    assert(volume[0] == 12 && frequency[0] == (900u * 65536 + 24000) / 48000);
    sound_frame();
    assert(volume[0] == 6);
    sound_frame();
    assert(volume[0] == 0);
    sound_frame();
    sound_reset();
    sound_play(SFX_START);
    sound_play(SFX_START);
    sound_play(SFX_START);
    sound_frame();
    unsigned f = frequency[0];
    sound_play(SFX_SHOT);
    sound_frame(); /* 满时低优先级丢弃 */
    assert(frequency[0] != (900u * 65536 + 24000) / 48000);
    sound_play(SFX_END);
    sound_frame(); /* 高优先级抢一个 */
    assert(frequency[0] == (660u * 65536 + 24000) / 48000);
    assert(f != 0);
    sound_reset();
    sound_play(SFX_BOMB);
    sound_frame();
    unsigned before = calls[3];
    sound_play(SFX_SLASH);
    sound_frame();
    assert(calls[3] == before + 1 && volume[3] > 24);
    sound_reset();
    sound_play(SFX_MENU_OK);
    for (int i = 0; i < 4; i++)
        sound_frame();
    sound_frame();
    assert(frequency[0] == (1200u * 65536 + 24000) / 48000);
    for (int i = 0; i < 6; i++)
        sound_frame();
    assert(volume[0] == 0);
    sound_play((sfx_id)-1);
    sound_frame();
    for (unsigned i = 0; i < SFX_COUNT; i++) {
        sound_reset();
        sound_play((sfx_id)i);
        for (int t = 0; t < 70; t++)
            sound_frame();
        for (int ch = 0; ch < 4; ch++)
            assert(volume[ch] == 0);
    }
    puts("sound: 包络、两步音效、优先级抢占、全表自停通过");
}
