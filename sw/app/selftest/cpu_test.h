/* CPU 和内存自检 */
#ifndef CPU_TEST_H
#define CPU_TEST_H

#include <stdint.h>

/* 返回 0 = 通过, 否则是 FAIL 码:
 * 2 = 有初值的变量不对 (复位后没从 ROM 恢复), 3 = .bss 不是 0,
 * 4 = RAM 读写不一致, 5 = 函数调用/栈出错, 6 = 字节/半字写不对 */
uint32_t cpu_test(void);

#endif
