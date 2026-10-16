/* CoreMark 移植层 (AMa-s-RISCV, rtl/soc_top, 裸机)
 *
 * CoreMark 的算法文件在 third_party/coremark/, 一字不改; 它要求移植者提供:
 *   1. 计时: start_time / stop_time / get_time / time_in_secs   -> core_portme.c, 用 cycle 计数器
 *   2. 输出: ee_printf                                          -> ee_printf.c, 走 UART
 *   3. 初始化/收尾: portable_init / portable_fini                -> core_portme.c
 *   4. 本文件里的类型和配置宏
 * 改编自官方 barebones/core_portme.h。
 */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>
#include <stdint.h>

/* 没有浮点单元也没有软浮点库 (-nostdlib): 用整数秒。
 * 精确的 CoreMark/MHz 由 Total ticks (= 时钟周期数) 和 Iterations 算, 见 scripts/coremark.py */
#define HAS_FLOAT  0
#define HAS_TIME_H 0
#define USE_CLOCK  0
#define HAS_STDIO  0
#define HAS_PRINTF 0

#ifndef COMPILER_VERSION
#ifdef __clang__
#define COMPILER_VERSION "clang " __clang_version__
#else
#define COMPILER_VERSION "GCC " __VERSION__
#endif
#endif
#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS FLAGS_STR   /* 构建脚本用 -DFLAGS_STR=\"...\" 传入实际编译选项 */
#endif
#define MEM_LOCATION "STATIC (on-chip RAM 0x10000000)"

typedef int16_t  ee_s16;
typedef uint16_t ee_u16;
typedef int32_t  ee_s32;
typedef int32_t  ee_f32;      /* HAS_FLOAT=0, 不会真正用到浮点 */
typedef uint8_t  ee_u8;
typedef uint32_t ee_u32;
typedef ee_u32   ee_ptr_int;  /* 必须能装下一个指针: rv32 指针 32 位 */
typedef size_t   ee_size_t;

#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3))

/* 计时单位 = CPU 时钟周期 (cycle CSR)。CORE_TICKS 是 32 位:
 * 50 MHz 下最多约 85 秒, 跑 10~20 秒没问题; 主频提到 200 MHz 以上要注意回绕 */
#define CORETIMETYPE ee_u32
typedef ee_u32 CORE_TICKS;

#define SEED_METHOD SEED_VOLATILE   /* 种子放在 volatile 变量里, 编译器没法提前算出结果 */
#define MEM_METHOD  MEM_STATIC      /* 2 KB 数据块用静态数组 (.bss), 不需要 malloc */

#define MULTITHREAD 1               /* 单核 */
#define USE_PTHREAD 0
#define USE_FORK    0
#define USE_SOCKET  0

#define MAIN_HAS_NOARGC   1         /* 裸机 main 没有命令行参数 */
#define MAIN_HAS_NORETURN 0

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S
{
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

#if !defined(PROFILE_RUN) && !defined(PERFORMANCE_RUN) \
    && !defined(VALIDATION_RUN)
#if (TOTAL_DATA_SIZE == 1200)
#define PROFILE_RUN 1
#elif (TOTAL_DATA_SIZE == 2000)
#define PERFORMANCE_RUN 1
#else
#define VALIDATION_RUN 1
#endif
#endif

int ee_printf(const char *fmt, ...);

#endif /* CORE_PORTME_H */
