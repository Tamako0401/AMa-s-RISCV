/* 复位后变量是否回到初值, 只给 tests/soc/reset_tb.sv 用 (结果写 tohost, 上板看不到任何现象)
 * 第一次和复位后的每一次运行都应看到 lives == 3; 看到别的值说明 .data 没从 ROM 恢复。
 * tohost: 1 = 通过, 2 = 初值不对, 3 = .bss 不是 0 */
#include <stdint.h>

volatile uint64_t tohost __attribute__((section(".tohost")));

static volatile int lives = 3;   /* 有初值 -> .data, 初值存放在 ROM */
static volatile int score;       /* 无初值 -> .bss, startup.S 清零 */

int main(void)
{
    int result = 1;
    if (lives != 3) result = 2;
    else if (score != 0) result = 3;
    lives = 1;                   /* 改掉: 复位后应该重新看到 3 */
    score = 100;
    tohost = result;
    for (;;) {}
}
