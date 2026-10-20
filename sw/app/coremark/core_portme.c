/* CoreMark 移植层: 计时、初始化、收尾 (改编自官方 barebones/core_portme.c)
 *
 * 计时用 RISC-V 的 cycle 计数器 (rtl/core/csr_reg.v): 复位后每个时钟加 1。
 * 所以 "tick" 就是时钟周期, 每秒 tick 数 = 主频 SYSCLK_HZ。
 * 仿真和实机跑的是同一份 RTL, 同样的程序在两边花的周期数一样,
 * 因此 CoreMark/MHz 在仿真里就能算准; 上板只是用真实主频把它跑满 10 秒。
 */
#include "coremark.h"
#include "core_portme.h"
#include "bsp.h"
#include "uart.h"

/* 种子: 性能跑 (2K 数据块) 规定为 0, 0, 0x66。放在 volatile 变量里, 编译器读不到具体值 */
#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
/* 迭代次数; 0 = CoreMark 自己试跑, 估出够 10 秒的次数 */
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

/* 仿真测试台 (tests/soc/coremark_tb.sv) 看到这里被写入就结束仿真; 实机上没人看, 无害 */
volatile uint64_t tohost __attribute__((section(".tohost")));

int coremark_errors;
static CORETIMETYPE start_time_val, stop_time_val;

static inline ee_u32 read_cycle(void)
{
    ee_u32 c;
    __asm__ volatile("csrr %0, cycle" : "=r"(c));
    return c;
}

void start_time(void)
{
    start_time_val = read_cycle();
}

void stop_time(void)
{
    stop_time_val = read_cycle();
}

/* 无符号减法: 中间计数器回绕一次也能得到正确差值 */
CORE_TICKS
get_time(void)
{
    return (CORE_TICKS)(stop_time_val - start_time_val);
}

/* HAS_FLOAT=0, 返回整数秒 (向下取整); 只用于 "够不够 10 秒" 的判断和粗略显示 */
secs_ret time_in_secs(CORE_TICKS ticks)
{
    return ticks / SYSCLK_HZ;
}

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    ee_printf("\nAMa-s-RISCV CoreMark, clock %lu Hz\n", (unsigned long)SYSCLK_HZ);
    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
        ee_printf("ERROR! Please define ee_ptr_int to a type that holds a pointer!\n");
    if (sizeof(ee_u32) != 4)
        ee_printf("ERROR! Please define ee_u32 to a 32b unsigned type!\n");
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    p->portable_id = 0;
    core_results *result = (core_results *)((char *)p - offsetof(core_results, port));
    uint64_t scaled = (uint64_t)result->iterations * 1000000000u;
    ee_u32 ticks = get_time(), score = 0;
    /* 裸机 clang 没有 64 位除法库; 这里只求千分位, 减法次数很少。 */
    if (ticks) {
        while (scaled >= ticks) {
            scaled -= ticks;
            score++;
        }
    }
    ee_printf("[result] CoreMark/MHz %lu.%03lu\n", (unsigned long)(score / 1000), (unsigned long)(score % 1000));
#ifdef MIN_SCORE
    if (score < MIN_SCORE)
        coremark_errors++;
#endif
    ee_printf("CoreMark done.\n");
    tohost = ticks && !coremark_errors ? 1 : 2;
}

/* -nostdlib 没有 C 库, 但编译器会为结构体赋值/清零自动生成 memcpy/memset 调用 */
void *memcpy(void *dst, const void *src, size_t n)
{
    ee_u8 *d = dst;
    const ee_u8 *s = src;
    while (n--)
        *d++ = *s++;
    return dst;
}

void *memset(void *dst, int c, size_t n)
{
    ee_u8 *d = dst;
    while (n--)
        *d++ = (ee_u8)c;
    return dst;
}
