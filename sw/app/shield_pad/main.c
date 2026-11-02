/* shield_pad: GameShield PAD 版 (mes50hp) 当无线手柄。
 *   每 1/60 秒读 9 个按键 + 摇杆 4 个方向, 拼成 'P' 帧 (game/board/pad.h, 和电脑 tools/ama/pad.py 发的一样),
 *   经第二个串口发给星闪 WS63 (aux_uart.h), 对面 100HP 上的 game 从它的第二个串口收。
 *   按键有变化时控制台串口打一行, LED 亮 = 有键按着。
 * 发的一方停了, 主机 0.5 秒收不到 'P' 帧就当松开 (pad.h 的 PAD_STALE), 不会卡键。 */
#include "app_board.h" /* 本板接线: boards/<板>/ */
#include "aux_uart.h"
#include "bsp.h"
#include "io.h"
#include "pad.h"
#include "uart.h"

static const uint32_t key_pins[] = PAD_KEY_PINS;
static const uint32_t joy_pins[] = PAD_JOY_PINS;
#define N(a) (sizeof(a) / sizeof((a)[0]))

/* 键 -> pad.h 的位: 前 7 个在 keys 字节, RESTART / MENU 在 btn 字节 (bit0 / bit1), 同 pad.py */
static const uint32_t key_bits[] = {PAD_UP, PAD_DOWN, PAD_LEFT,    PAD_RIGHT, PAD_A,
                                    PAD_B,  PAD_SLOW, PAD_RESTART, PAD_MENU};
static const uint32_t joy_bits[] = {PAD_UP, PAD_DOWN, PAD_LEFT, PAD_RIGHT};

static uint32_t read_pad(void)
{
    uint32_t held = 0;
    for (uint32_t i = 0; i < N(key_pins); i++)
        if (!io_read(key_pins[i])) /* 按下接地 */
            held |= key_bits[i];
    for (uint32_t i = 0; i < N(joy_pins); i++)
        if (!io_read(joy_pins[i]))
            held |= joy_bits[i];
    return held;
}

/* game/board/link.h 的帧: [0xFF] [类型] [长度] [数据] [校验], 0xFF 之后每个字节都 < 0x80 */
static void send_p(uint32_t held)
{
    uint8_t body[8] = {
        'P', 6, (uint8_t)(held & 0x7F), (uint8_t)((held & PAD_RESTART ? 1 : 0) | (held & PAD_MENU ? 2 : 0)), 0, 0,
        0,   0};
    uint32_t sum = 0;
    uart_putc(AUX_UART, (char)0xFF);
    for (uint32_t i = 0; i < sizeof body; i++) {
        uart_putc(AUX_UART, (char)body[i]);
        sum += body[i];
    }
    uart_putc(AUX_UART, (char)(sum & 127));
}

static void put_hex(uint32_t v)
{
    for (int s = 8; s >= 0; s -= 4)
        uart_putc(CONSOLE_UART, "0123456789abcdef"[(v >> s) & 15]);
}

int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    aux_uart_init(115200);
    io_dir(LED, IO_OUTPUT);
    uart_puts(CONSOLE_UART, "shield_pad: 60 'P' frames/s to WS63\r\n");
    uint32_t last = 0, next = bsp_cycles();
    for (;;) {
        while ((int32_t)(bsp_cycles() - next) < 0)
            ;
        next += SYSCLK_HZ / 60;
        uint32_t held = read_pad();
        send_p(held);
        io_write(LED, held != 0);
        if (held != last) {
            uart_puts(CONSOLE_UART, "keys ");
            put_hex(held);
            uart_puts(CONSOLE_UART, "\r\n");
            last = held;
        }
    }
}
