#include <stdint.h>
volatile uint64_t tohost __attribute__ ((section(".tohost")));
volatile uint64_t fromhost __attribute__ ((section(".tohost")));

volatile int g_result;

int main(void) {
    g_result = 0;
    while(1) {
        if (g_result == 0721) {
            tohost = 1;
            return 0;
        }
        g_result += 5;
    }
}
