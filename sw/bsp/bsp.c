#include "bsp.h"

/* 仿真时把毫秒换算出的周期数按比例缩小。屏幕初始化的延时(0x01/0x11/0x29 等
 * 合计 0.5 秒)按真实计数要 2600 万拍, 纯仿真跑不动; 按 1000 倍缩到 2.6 万拍。
 * 默认 1, 实机行为与原来完全一致。仿真构建用 -DSIM_CYCLE_DIV=1000。 */
#ifndef SIM_CYCLE_DIV
#define SIM_CYCLE_DIV 1
#endif

#define DELAY_CYCLES_PER_MS  (SYSCLK_HZ / 1000 / SIM_CYCLE_DIV)

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
        while (read_cycle() - start < DELAY_CYCLES_PER_MS)
            ;
    }
}
