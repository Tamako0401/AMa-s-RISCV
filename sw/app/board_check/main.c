/* 上板自检: 串口打印结果, 回显收到的字符, LED 流水表示 CPU 在跑。
 * 串口 115200 8N1。按 KEY1 复位后应再次打印 PASS (检查 .data 初值从 ROM 恢复)。
 * 输出与 sw/board/main.c 相同, 所以复用板级测试台 tests/board/board_tb.sv。
 * FAIL 码: 2 = 有初值的变量不对 (复位后没从 ROM 恢复), 3 = .bss 不是 0,
 *          4 = RAM 读写不一致, 5 = 函数调用/栈出错, 6 = 字节/半字写不对 */
#include "bsp.h"
#include "uart.h"

#define LED_STEP_MS 500

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

static uint32_t self_test(void)
{
    if (boot_marker != 0x12345678) return 2;
    boot_marker = 0;                                 /* 改掉, KEY1 后应恢复 */
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

static void show_leds(uint32_t pattern)             /* 只动 LED 那 8 位, 不碰屏幕的 GPIO 0~2 */
{
    gpio_reset(GPIO, LED_PINS & ~(pattern << LED_SHIFT));
    gpio_set(GPIO, pattern << LED_SHIFT);
}

int main(void)
{
    gpio_reset(GPIO, LED_PINS);
    gpio_set_mode(GPIO, LED_PINS, GPIO_MODE_OUTPUT);
    show_leds(1);
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);

    uint32_t error = self_test();
    if (error) {
        show_leds(0x80 | error);                     /* 最高位亮 + 低位是 FAIL 码 */
        uart_puts(CONSOLE_UART, "AMA CPU FAIL ");
        uart_putc(CONSOLE_UART, '0' + error);
        uart_puts(CONSOLE_UART, "\r\n");
        for (;;)
            ;
    }
    uart_puts(CONSOLE_UART, "AMA CPU PASS\r\n");

    uint32_t step = bsp_ms_to_cycles(LED_STEP_MS);
    uint32_t last = bsp_cycles(), pattern = 1;
    for (;;) {
        if (bsp_cycles() - last >= step) {           /* 每 0.5 秒移一位 */
            last += step;
            pattern = pattern == 0x80 ? 1 : pattern << 1;
            show_leds(pattern);
        }
        char c;
        if (uart_getc(CONSOLE_UART, &c))             /* 收到什么就回什么 */
            uart_putc(CONSOLE_UART, c);
    }
}
