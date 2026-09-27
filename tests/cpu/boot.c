/* Exercises startup, initialized data, BSS, stack, calls and load-use chains. */
volatile unsigned results[32];
volatile unsigned initialized = 0x12345678;
__attribute__((noinline)) static unsigned sum(unsigned n) {
    volatile unsigned local[8];
    for (unsigned i = 0; i < 8; ++i) local[i] = n + i;
    unsigned s = 0;
    for (unsigned i = 0; i < 8; ++i) s += local[i];
    return s;
}
int main(void) {
    if (initialized != 0x12345678) return 2;
    for (unsigned i = 0; i < 32; ++i) if (results[i]) return 3;
    for (unsigned i = 0; i < 32; ++i) results[i] = sum(i);
    unsigned total = 0;
    for (unsigned i = 0; i < 32; ++i) total += results[i];
    return total == 4864 ? 1 : 4;
}
