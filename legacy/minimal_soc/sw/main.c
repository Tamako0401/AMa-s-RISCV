typedef unsigned int u32;
#define REG(a) (*(volatile u32 *)(a))
#define UART 0x30000000u
#define GPIO 0x40000000u
#ifndef HEARTBEAT_CYCLES
#define HEARTBEAT_CYCLES 25000000u
#endif
static volatile u32 scratch[64];
static volatile u32 initialized = 0x12345678u;
static void putc_uart(char c) {
    while (REG(UART+4) & 1u) {}
    REG(UART+12) = (unsigned char)c;
}
static void puts_uart(const char *s) { while (*s) putc_uart(*s++); }
static u32 cycles(void) {
    u32 n; __asm__ volatile ("rdcycle %0" : "=r"(n)); return n;
}
__attribute__((noinline)) static u32 sum(u32 n) {
    volatile u32 a[8];
    for (u32 i=0; i<8; ++i) a[i] = n+i;
    u32 result=0;
    for (u32 i=0; i<8; ++i) result += a[i];
    return result;
}
int main(void) {
    REG(GPIO) = 0x55550000; // GPIO 8~15 outputs -> LED; 0~2 reserved for the LCD
    REG(GPIO+4) = 1u << 8;
    REG(UART+8) = 433; // 50 MHz / (433+1), approx. 115207 baud
    REG(UART) = 3; // TX + RX
    u32 error = initialized != 0x12345678u ? 2 : 0;
    for (u32 i=0; i<64; ++i) if (scratch[i] != 0) error = 3;
    for (u32 i=0; i<64; ++i) scratch[i] = 0xa5a50000u ^ i;
    for (u32 i=0; i<64; ++i) if (scratch[i] != (0xa5a50000u ^ i)) error = 4;
    if (sum(10) != 108) error = 5;
    scratch[0] = 0x89abcdefu;
    ((volatile unsigned char *)scratch)[1] = 0x12;
    ((volatile unsigned short *)scratch)[1] = 0x7654;
    if (scratch[0] != 0x765412efu) error = 6;
    if (error) {
        REG(GPIO+4) = (0x80 | error) << 8;
        puts_uart("AMA CPU FAIL "); putc_uart('0'+error); puts_uart("\r\n");
        for (;;) {}
    }
    puts_uart("AMA CPU PASS\r\n");
    u32 previous=cycles(), pattern=1;
    for (;;) {
        if ((u32)(cycles()-previous) >= HEARTBEAT_CYCLES) {
            previous=cycles();
            pattern = pattern == 128 ? 1 : pattern << 1;
            REG(GPIO+4) = pattern << 8;
        }
        if (REG(UART+4) & 2u) {
            char c = (char)REG(UART+16);
            REG(UART+4) = 0; // clear RX complete
            putc_uart(c);
        }
    }
}
