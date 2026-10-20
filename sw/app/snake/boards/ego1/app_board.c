#include "app_board.h"
#include "io.h"

key_t keys[KEY_N] = {
    [K_UP] = { .pin = PIN_S4 },
    [K_DOWN] = { .pin = PIN_S1 },
    [K_LEFT] = { .pin = PIN_S3 },
    [K_RIGHT] = { .pin = PIN_S0 },
    [K_START] = { .pin = PIN_S2 },
};

void read_settings(int *uart_on, int *wrap)
{
    *wrap = io_read(SW_WRAP);
    *uart_on = io_read(SW_UART);
}
