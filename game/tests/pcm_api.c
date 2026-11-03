/* 核对共同 PCM C 接口的寄存器偏移、符号打包、容量和4样本对齐。 */
#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <sys/mman.h>
#include "audio.h"
int main(void)
{
    volatile uint32_t *regs =
        mmap((void *)AUDIO_BASE, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    assert(regs != MAP_FAILED);
    audio_pcm_enable(1, 3);
    assert(regs[0x50 / 4] == 0x31);
    audio_pcm_volume(96);
    assert(regs[0x5c / 4] == 96);
    regs[0x58 / 4] = 2044 | (123u << 16);
    assert(audio_pcm_space() == 4 && audio_pcm_underruns() == 123);
    const int8_t samples[] = {-128, -1, 0, 127, 1, 2, 3, 4};
    assert(audio_pcm_write(samples, 8) == 4 && regs[0x54 / 4] == 0x7f00ff80);
    assert(audio_pcm_write(samples, 3) == 0);
    regs[0x58 / 4] = 2048;
    assert(audio_pcm_write(samples, 4) == 0);
    audio_pcm_enable(0, 3);
    assert(regs[0x50 / 4] == 0x30);
    munmap((void *)regs, 4096);
    puts("PCM API: offsets, FIFO space, signed samples, alignment, underruns passed");
    return 0;
}
