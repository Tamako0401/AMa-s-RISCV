/* shield_host: GameShield 的声音和第二个串口 (mes2l100hp)。
 *   按键: 四个键各响一个音 (C5 E5 G5 C6, 方波 120 ms, 自己停), 串口打印 "key n"。
 *   第二个串口 (星闪 WS63): 收到什么回什么, 同时转到控制台串口, 每个字节响一下短的 "嘀";
 *   控制台串口 (ama monitor) 打的字发到第二个串口, 用来从电脑经 WS63 发东西。
 *   LED 每 0.5 秒亮灭一次。
 * 其他板没有功放和第二个串口的约定接法, 照样能跑, 只是不出声、第二个串口不通。 */
#include "aux_uart.h"
#include "board_audio.h"
#include "bsp.h"
#include "io.h"
#include "key.h"
#include "uart.h"
#include "app_board.h" /* 本板接线: boards/<板>/ */

#define KEY_N 4

static const uint32_t key_pins[KEY_N] = KEYS;
static const uint32_t notes[KEY_N] = {AUDIO_HZ(523), AUDIO_HZ(659), AUDIO_HZ(784), AUDIO_HZ(1047)};
static key_t keys[KEY_N];

int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    aux_uart_init(115200);
    board_audio_init();
    uart_puts(CONSOLE_UART, "shield_host: keys beep, UART2 echo\r\n");
    uart_puts(AUX_UART, "shield_host\r\n");
    audio_beep(AUDIO_SQUARE0, AUDIO_HZ(880), 80, AUDIO_MS(60)); /* 开机响一下 */

    for (uint32_t i = 0; i < KEY_N; i++)
        keys[i].pin = key_pins[i];
    io_dir(LED, IO_OUTPUT);
    uint32_t step = bsp_ms_to_cycles(500), last = bsp_cycles();
    int on = 0;
    for (;;) {
        if (bsp_cycles() - last >= step) {
            last += step;
            on = !on;
            io_write(LED, on);
        }
        key_ticks(keys, KEY_N);
        for (uint32_t i = 0; i < KEY_N; i++)
            if (key_rose(&keys[i])) {
                audio_beep(AUDIO_SQUARE0, notes[i], 120, AUDIO_MS(120));
                uart_puts(CONSOLE_UART, "key ");
                uart_putc(CONSOLE_UART, (char)('1' + i));
                uart_puts(CONSOLE_UART, "\r\n");
            }
        char c;
        if (uart_getc(AUX_UART, &c)) {
            uart_putc(AUX_UART, c);
            uart_putc(CONSOLE_UART, c);
            audio_beep(AUDIO_SQUARE1, AUDIO_HZ(1760), 40, AUDIO_MS(15));
        }
        if (uart_getc(CONSOLE_UART, &c))
            uart_putc(AUX_UART, c);
    }
}
