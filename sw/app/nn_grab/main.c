/* nn_grab: 把板子 handnet 实际看到的 160x120 输入画面经串口送回电脑, 和电脑那边的画面/训练数据对比。
 *
 * 电脑 (model/board_grab.py) 发一个 'g': 抓下一个完整 HDMI 输入帧 -> 自动推理 -> 回
 *     "NNGRAB <热力图 0..255> <x> <y> <握拳>\n" + 19200 个像素 x 3 字节 (行优先, R G B)。
 * 坏帧或超时回 "NNGRAB ERR <码>\n"。HDMI 输入的初始化和补设置同 game。 */
#include "board_hdmi.h"
#include "bsp.h"
#include "nn.h"
#include "nn_post.h"
#include "uart.h"

static void put_num(uint32_t v)
{
    char buf[11];
    int i = 10;
    buf[i] = 0;
    do {
        buf[--i] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    uart_puts(CONSOLE_UART, buf + i);
}

static void grab(void)
{
    nn_capture();
    int r = nn_capture_wait(50000000);
    if (r) {
        uart_puts(CONSOLE_UART, "NNGRAB ERR ");
        put_num((uint32_t)-r);
        uart_puts(CONSOLE_UART, "\n");
        NN->CTRL = NN_CTRL_CLEAR;
        return;
    }
    nn_hand_t h;
    nn_decode(&h);
    uart_puts(CONSOLE_UART, "NNGRAB ");
    put_num(h.heat);
    uart_puts(CONSOLE_UART, " ");
    put_num(h.x);
    uart_puts(CONSOLE_UART, " ");
    put_num(h.y);
    uart_puts(CONSOLE_UART, " ");
    put_num((uint32_t)h.fist);
    uart_puts(CONSOLE_UART, "\n");
    for (uint32_t i = 0; i < NN_IN_W * NN_IN_H; i++) {
        uint32_t p = nn_get(i);
        uart_putc(CONSOLE_UART, (char)(p >> 16));
        uart_putc(CONSOLE_UART, (char)(p >> 8));
        uart_putc(CONSOLE_UART, (char)p);
    }
    NN->CTRL = NN_CTRL_CLEAR;
}

int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    int hdmi = board_hdmi_init();
    uart_puts(CONSOLE_UART, hdmi & 2 ? "nn_grab: HDMI in no answer\n" : "nn_grab: ready, send 'g'\n");
    uint32_t last_poll = bsp_cycles();
    for (;;) {
        if (bsp_cycles() - last_poll > SYSCLK_HZ / 15) { /* 隔一阵查一下 HDMI 输入, 锁定后补设置 */
            last_poll = bsp_cycles();
            if (board_hdmi_poll())
                uart_puts(CONSOLE_UART, "nn_grab: HDMI in locked\n");
        }
        char c;
        if (uart_getc(CONSOLE_UART, &c) && c == 'g')
            grab();
    }
}
