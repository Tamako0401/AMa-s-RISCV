/* nn_demo: 在片上跑一遍 handnet, 串口打印手心位置、握拳和耗时。
 *
 * 现在还没有"摄像头 -> 加速器"的直连通路 (见 docs/nn.md 的"下一步"), 所以这里自己造一张
 * 深色背景 + 亮块的图送进去, 顺便当作硬件自检: 打印的校验和应当等于
 * `model/nnref.py --demo` 在同一份模型上算出来的值。
 * 换真实权重、接上摄像头之后, 只要换掉 load_frame() 这一处。 */
#include "app_board.h" /* 本板接线: boards/<板>/ */
#include "bsp.h"
#include "nn.h"
#include "nn_post.h"
#include "uart.h"

/* 一边造图一边写进加速器 (不在 RAM 里留一整帧: 64 KiB 的 RAM 放不下 160*120*3)。
 * 深色背景上一个亮块, 位置和 nn_demo 的说明一致。 */
static void load_frame(void)
{
    NN->IN_ADDR = 0;
    for (uint32_t y = 0; y < 120; y++) {
        for (uint32_t x = 0; x < 160; x++) {
            int in_blob = x >= 50 && x < 120 && y >= 30 && y < 90;
            nn_put(in_blob ? 208 : 20, in_blob ? 162 : 22, in_blob ? 141 : 26);
        }
    }
}

static void put_uint(uint32_t v)
{
    char buf[11];
    int n = 0;
    if (v == 0) {
        uart_putc(CONSOLE_UART, '0');
        return;
    }
    while (v) {
        buf[n++] = (char)('0' + v % 10);
        v /= 10;
    }
    while (n)
        uart_putc(CONSOLE_UART, buf[--n]);
}

static void put_hex(uint32_t v)
{
    for (int shift = 28; shift >= 0; shift -= 4) {
        uint32_t nib = (v >> shift) & 15;
        uart_putc(CONSOLE_UART, (char)(nib < 10 ? '0' + nib : 'a' + nib - 10));
    }
}

int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    uart_puts(CONSOLE_UART, "\r\nhandnet accelerator\r\n");
    uart_puts(CONSOLE_UART, "硬件版本 ");
    put_hex(NN->VERSION);
    uart_puts(CONSOLE_UART, ", 输入 ");
    put_uint(NN->IN_PIX);
    uart_puts(CONSOLE_UART, " 像素, 网络 ");
    put_uint(NN_LAYERS);
    uart_puts(CONSOLE_UART, " 层\r\n");

    for (;;) {
        uint32_t t0 = bsp_cycles();
        load_frame();
        uint32_t t1 = bsp_cycles();
        nn_start();
        if (nn_wait(2000000) != 0) {
            uart_puts(CONSOLE_UART, "推理超时\r\n");
            delay_ms(1000);
            continue;
        }
        uint32_t t2 = bsp_cycles();

        nn_hand_t h;
        nn_decode(&h);
        uart_puts(CONSOLE_UART, "手 ");
        if (h.found) {
            uart_puts(CONSOLE_UART, "(");
            put_uint(h.x);
            uart_puts(CONSOLE_UART, ",");
            put_uint(h.y);
            uart_puts(CONSOLE_UART, ") ");
        } else {
            uart_puts(CONSOLE_UART, "没找到 ");
        }
        uart_puts(CONSOLE_UART, h.fist ? "握拳" : "张开");
        uart_puts(CONSOLE_UART, " 分数 ");
        put_uint(h.heat);
        uart_puts(CONSOLE_UART, " 送图 ");
        put_uint(t1 - t0);
        uart_puts(CONSOLE_UART, " 拍, 推理 ");
        put_uint(t2 - t1);
        uart_puts(CONSOLE_UART, " 拍, 校验和 ");
        put_hex(nn_checksum());
        uart_puts(CONSOLE_UART, "\r\n");

        delay_ms(1000);
    }
}
