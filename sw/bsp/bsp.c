#include "bsp.h"

static inline uint32_t read_cycle(void)
{
    uint32_t c;
    __asm__ volatile ("csrr %0, cycle" : "=r"(c));
    return c;
}

/* 用 cycle 计数器计时, 与 CPU 每条指令花几拍无关. 单次不超过约 85 秒(32 位回绕) */
void delay_ms(uint32_t ms)
{
    while (ms--) {
        uint32_t start = read_cycle();
        while (read_cycle() - start < SYSCLK_HZ / 1000)
            ;
    }
}
