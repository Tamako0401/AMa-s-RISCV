/* 使用原有 sw/board/start.S 和 link.ld, 不在测试固件里补 .data 恢复逻辑。
 * GPIO DATA 的写事务充当观测信箱, 无需 UART 或修改 RTL。 */
volatile unsigned reset_value = 3;

int main(void)
{
    volatile unsigned *report = (volatile unsigned *)0x40000004;
    *report = reset_value;
    reset_value = 1;
    *report = 0xc001cafe;  /* 前两个访问完成, 可安全按 KEY1 */
    for (;;) __asm__ volatile ("nop");
}
