/* nn_check: SoC 级接线自检 —— handnet 加速器真的挂在总线上了吗。
 *
 * 逐字节的数值比对在 tests/nn/nn_tb.sv (那是加速器内部的事); 这里只查接线:
 *   1. VERSION、IN_PIX 读得对 (地址译码和外设口没错位);
 *   2. 一次推理能跑完 (busy 拉低、done 拉高), 校验和不为 0;
 *   3. 换一张输入图, 校验和必须变 (CPU 写的像素真的进了网络)。
 * 通过: 向结束信箱 0x1000_0000 写 1。 */
#include <stdint.h>

#include "amarisc.h"
#include "nn.h"

#define MAILBOX (*(volatile uint32_t *)0x10000000)

/* 把结果写进结束信箱并停住: soc_tb 拿它当退出码 */
static void report(uint32_t code)
{
    MAILBOX = code;
    for (;;) {
    }
}

static void fill_frame(uint32_t salt)
{
    NN->IN_ADDR = 0;
    for (uint32_t y = 0; y < 120; y++) {
        for (uint32_t x = 0; x < 160; x++) {
            int in_blob = x >= 50 && x < 120 && y >= 30 && y < 90;
            uint32_t r = (in_blob ? 200 : 20) + salt;
            uint32_t g = in_blob ? 160 : 22;
            uint32_t b = in_blob ? 140 : 26;
            NN->IN = r << 16 | g << 8 | b;
        }
    }
}

static uint32_t run(void)
{
    NN->CTRL = NN_CTRL_START;
    for (uint32_t n = 0; n < 3000000; n++) {
        if (NN->STATUS & NN_STATUS_DONE)
            return nn_checksum();
    }
    return 0;
}

int main(void)
{
    if (NN->VERSION != 0x4e4e0001UL)
        report(3);
    if (NN->IN_PIX != NN_IN_W * NN_IN_H)
        report(4);

    fill_frame(0);
    uint32_t a = run();
    if (a == 0)
        report(5);

    fill_frame(7);
    uint32_t b = run();
    if (b == 0)
        report(6);
    if (b == a)
        report(7);
    if (nn_busy())
        report(8);

    report(1);
}
