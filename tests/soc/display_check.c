/* 新显示 (rib s3, 0x3000_0000) 的 SoC 级驱动: 按 refmodel.py export --soc 生成的
 * display_script[] 把一帧写进显示、提交、等生效 -- 走的是真的 CPU + 总线路径,
 * 也是板上游戏每帧要做的事 (见 docs/display.md "每帧怎么用")。
 * 就绪后从信箱 0x1000_0000 依次报 最忙一行 / 超时行 / 丢掉对象, 最后写 0x600D600D,
 * 然后自旋: 收帧比对由测试台做, 不按"信箱 = 程序结束"的惯例 (那会停时钟, 画面就没了)。
 * 挂在 tests/soc/display_tb.sv。 */
#include <stdint.h>

#define DISPLAY ((volatile uint32_t *)0x30000000)
#define MAILBOX (*(volatile uint32_t *)0x10000000)

#define REG_COMMIT 0x1C
#define REG_FRAME 0x24
#define REG_LINE_MAX 0x28
#define REG_OVERRUN 0x2C
#define REG_DROPPED 0x30

extern const uint32_t display_script[]; /* prepare 生成的 {out}/script.c */

int main(void)
{
    const uint32_t *s = display_script;
    uint32_t f;

    for (;;) {
        uint32_t addr = *s++;
        volatile uint32_t *p;
        uint32_t count;

        if (addr == 0xFFFFFFFF)
            break;
        count = *s++;
        p = DISPLAY + addr / 4;
        while (count--)
            *p++ = *s++;
    }

    DISPLAY[REG_COMMIT / 4] = 1;
    while (DISPLAY[REG_COMMIT / 4] & 1) /* 提交在下一个场消隐开头生效, 这位清 0 = 换好了 */
        ;
    /* 再等一整帧: LINE_MAX 这些统计数的是"上一帧", 刚换上去时还是旧参数那帧的数 */
    f = DISPLAY[REG_FRAME / 4];
    while (DISPLAY[REG_FRAME / 4] == f)
        ;

    MAILBOX = DISPLAY[REG_LINE_MAX / 4];
    MAILBOX = DISPLAY[REG_OVERRUN / 4];
    MAILBOX = DISPLAY[REG_DROPPED / 4];
    MAILBOX = 0x600D600D;
    for (;;) {
    }
}
