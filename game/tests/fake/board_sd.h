#ifndef FAKE_BOARD_SD_H
#define FAKE_BOARD_SD_H
#include <stdint.h>
#define SYSCLK_HZ 50000000u
void board_sd_init(void);
void board_sd_speed(int fast);
void board_sd_select(int on);
int board_sd_xfer(uint8_t v, uint8_t *r);
uint32_t bsp_cycles(void);
void delay_ms(uint32_t ms);
#endif
