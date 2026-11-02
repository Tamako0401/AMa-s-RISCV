#include "bsp.h"
#include "uart.h"
#include "sd.h"
#include "pak.h"
static pak_t pak;
static void hex(uint32_t v)
{
    for (int i = 28; i >= 0; i -= 4)
        uart_putc(CONSOLE_UART, "0123456789abcdef"[(v >> i) & 15]);
}
int main(void)
{
    uart_init(CONSOLE_UART, SYSCLK_HZ, 115200);
    int type = sd_init();
    uart_puts(CONSOLE_UART, type == 2 ? "SDHC\r\n" : type == 1 ? "SDSC\r\n" : "SD init failed\r\n");
    if (type && pak_mount(&pak, sd_read_block)) {
        uint8_t header[20];
        pak_read(&pak, 0, header, sizeof header);
        uart_puts(CONSOLE_UART, "AMAPAK1 version=1 count=0x");
        hex(pak.count);
        uart_puts(CONSOLE_UART, " bytes=0x");
        hex(pak.size);
        uart_puts(CONSOLE_UART, " LBA=0x");
        hex(pak.lba);
        pak_entry_t e;
        if (pak_find(&pak, PAK_PORTRAIT, 0, &e)) {
            uart_puts(CONSOLE_UART, "\r\nportrait0 bytes=0x");
            hex(e.length);
        }
        if (pak_find(&pak, PAK_BGM, 0, &e)) {
            uart_puts(CONSOLE_UART, "\r\nbgm0 bytes=0x");
            hex(e.length);
        }
        uart_puts(CONSOLE_UART, "\r\n");
    } else if (type)
        uart_puts(CONSOLE_UART, "PAK mount failed (FAT32/root/continuous/header)\r\n");
    for (;;)
        ;
}
