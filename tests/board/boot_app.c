#include "amarisc.h"

extern char _boot_start[];

void main(void)
{
    /* 用真实数据总线验证保护, 不让编译器把地址零当作空指针消掉。 */
    __asm__ volatile("sw zero, 0(%0)" ::"r"(0) : "memory");
    *(volatile uint32_t *)0x40004004 = 1;
    __asm__ volatile("sw zero, 0(%0)" ::"r"(_boot_start) : "memory");
    *(volatile uint32_t *)0x40004004 = 0;
    UART1->CTRL = 3;
    UART1->BAUD = 433;
#ifdef NEW_APP
    const char *s = "NEW APP\n";
#else
    const char *s = "DEFAULT APP\n";
#endif
    while (*s) {
        while (UART1->STATUS & UART_STATUS_TXBUSY)
            ;
        UART1->TXDATA = *s++;
    }
    for (;;)
        ;
}
