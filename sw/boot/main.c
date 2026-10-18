#include "bsp.h"

#define HW_ID (*(volatile uint32_t *)0x40004000)
#define ROM_WE (*(volatile uint32_t *)0x40004004)
#define APP_SIZE 0xf800u

static uint32_t cycles(void)
{
    uint32_t c;
    __asm__ volatile ("csrr %0, cycle" : "=r"(c));
    return c;
}

static int receive(uint32_t timeout)
{
    uint32_t start = cycles();
    do {
        if (UART1->STATUS & UART_STATUS_RXDONE) {
            uint32_t c = UART1->RXDATA;
            UART1->STATUS = 0;
            return c;
        }
    } while (cycles() - start < timeout);
    return -1;
}

static void send(uint32_t c)
{
    while (UART1->STATUS & UART_STATUS_TXBUSY) ;
    UART1->TXDATA = c;
}

static void send_word(uint32_t word)
{
    for (unsigned i = 0; i < 4; i++, word >>= 8) send(word & 255);
}

static int receive_word(uint32_t *word)
{
    *word = 0;
    for (unsigned i = 0; i < 32; i += 8) {
        int c = receive(100 * DELAY_CYCLES_PER_MS);
        if (c < 0) return 0;
        *word |= (uint32_t)c << i;
    }
    return 1;
}

static void go(void)
{
    __asm__ volatile ("jalr zero, zero, 0" ::: "memory");
    __builtin_unreachable();
}

void main(void)
{
    UART1->CTRL = 3;
    UART1->BAUD = SYSCLK_HZ / 115200 - 1;
    UART1->STATUS = 0;
    uint32_t start = cycles();
    uint32_t elapsed = 0;
    for (;;) {
        int c = receive(200 * DELAY_CYCLES_PER_MS - elapsed);
        if (c == 0x7f) break;
        elapsed = cycles() - start;
        if (elapsed >= 200 * DELAY_CYCLES_PER_MS) go();
    }
    for (;;) {
        send('A'); send('M'); send('B'); send(1);
        send_word(HW_ID); send_word(APP_SIZE);
        for (;;) {
            int c = receive(100 * DELAY_CYCLES_PER_MS);
            if (c < 0) continue;
            if (c == 'G') go();
            if (c != 'W') break;
            uint32_t length, expected;
            if (!receive_word(&length) || !receive_word(&expected)) break;
            if (length > APP_SIZE) {
                send('E'); send_word(0xffffffffu);
                continue;
            }
            ROM_WE = 1;
            uint32_t word = 0, i;
            for (i = 0; i < length; i++) {
                c = receive(100 * DELAY_CYCLES_PER_MS);
                if (c < 0) break;
                word |= (uint32_t)c << ((i & 3) << 3);
                if ((i & 3) == 3 || i + 1 == length) {
                    *(volatile uint32_t *)(i & ~3u) = word;
                    word = 0;
                }
            }
            ROM_WE = 0;
            if (i != length) break;
            uint32_t crc = 0xffffffffu;
            for (i = 0; i < length; i++) {
                crc ^= *(volatile uint8_t *)i;
                for (unsigned b = 0; b < 8; b++)
                    crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1)));
            }
            crc = ~crc;
            if (crc == expected) send('K');
            else { send('E'); send_word(crc); }
        }
        while (receive(100 * DELAY_CYCLES_PER_MS) != 0x7f) ;
    }
}
