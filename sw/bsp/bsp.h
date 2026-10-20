/* 板级支持: 时钟、延时、外部器件接线. 换板子只改这一层. */
#ifndef BSP_H
#define BSP_H

#include <stdint.h>
#include "amarisc.h"

#ifdef BOARD_EGO1
#include "ego1_pins.h"
#else
#include "mes50hp_pins.h"
#endif

#define SYSCLK_HZ 50000000UL /* MES50HP 板载 50MHz, 不经 PLL */

/* 仿真时把毫秒换算出的周期数按比例缩小。屏幕初始化的延时(0x01/0x11/0x29 等
 * 合计 0.5 秒)按真实计数要 2600 万拍, 纯仿真跑不动; 按 1000 倍缩到 2.6 万拍。
 * 默认 1, 实机行为与原来完全一致。仿真构建用 -DSIM_CYCLE_DIV=1000。 */
#ifndef SIM_CYCLE_DIV
#define SIM_CYCLE_DIV 1
#endif

#define DELAY_CYCLES_PER_MS (SYSCLK_HZ / 1000 / SIM_CYCLE_DIV)

#define CONSOLE_UART UART1

void delay_ms(uint32_t ms);
/* 自上电以来的时钟周期数 (32 位, 50MHz 下约 85 秒回绕, 用减法比较即可) */
uint32_t bsp_cycles(void);
/* 毫秒换算成周期数; 仿真构建 (SIM_CYCLE_DIV) 时同比例缩小。
 * 写成 static inline: rv32i 没有乘法指令, 编成普通函数时有的 clang 版本
 * 会调用 __mulsi3, 而 -nostdlib 下没有这个函数 (链接失败)。内联后参数是常量,
 * 编译时就算好了。 */
static inline uint32_t bsp_ms_to_cycles(uint32_t ms)
{
    return ms * DELAY_CYCLES_PER_MS;
}

// 实际两个板子的外设资源差异较大. 此处不强制统一bsp遮蔽.

#endif
