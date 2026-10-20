#include "cpu_test.h"

static volatile uint32_t boot_marker = 0x12345678;  /* .data: 初值在 ROM */
static volatile uint32_t scratch[64];               /* .bss: 应为 0 */

__attribute__((noinline)) static uint32_t sum8(uint32_t n)
{
    volatile uint32_t a[8];                          /* 放在栈上 */
    uint32_t r = 0;
    for (uint32_t i = 0; i < 8; i++) a[i] = n + i;
    for (uint32_t i = 0; i < 8; i++) r += a[i];
    return r;
}

uint32_t cpu_test(void)
{
    if (boot_marker != 0x12345678) return 2;
    boot_marker = 0;                                 /* 改掉, 复位后应恢复 */
    for (uint32_t i = 0; i < 64; i++) if (scratch[i] != 0) return 3;
    for (uint32_t i = 0; i < 64; i++) scratch[i] = 0xa5a50000u ^ i;
    for (uint32_t i = 0; i < 64; i++) if (scratch[i] != (0xa5a50000u ^ i)) return 4;
    for (uint32_t i = 0; i < 64; i++) scratch[i] = 0;   /* 还原, 下次复位前也不留脏数据 */
    if (sum8(10) != 108) return 5;
    volatile uint32_t w = 0x89abcdef;
    ((volatile uint8_t *)&w)[1] = 0x12;
    ((volatile uint16_t *)&w)[1] = 0x7654;
    if (w != 0x765412ef) return 6;
    return 0;
}
