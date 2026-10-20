#include "app_board.h"

key_t keys[KEY_N] = {
    [K_UP] = { .pin = PIN_KEY7 },
    [K_DOWN] = { .pin = PIN_KEY6 },
    [K_LEFT] = { .pin = PIN_KEY5 },
    [K_RIGHT] = { .pin = PIN_KEY8 },
    [K_START] = { .pin = PIN_KEY2 },
    [K_UART] = { .pin = PIN_KEY3 },
    [K_WRAP] = { .pin = PIN_KEY4 },
};

void read_settings(int *uart_on, int *wrap)
{
    if (key_rose(&keys[K_UART])) *uart_on = !*uart_on;
    if (key_rose(&keys[K_WRAP])) *wrap = !*wrap;
}
