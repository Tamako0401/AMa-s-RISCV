#include "board_hdmi.h"
#include "bsp.h"
#include "video.h"

volatile uint64_t tohost __attribute__((section(".tohost")));

static uint32_t solid(uint32_t color)
{
    return color * 0x11111111u;
}

int main(void)
{
    static const uint16_t colors[8] = {0xFFFF, 0xFFE0, 0x07FF, 0x07E0, 0xF81F, 0xF800, 0x001F, 0x0000};
    int status = board_hdmi_init();

    video_tile(0, (uint32_t[8]){solid(1), solid(1), solid(1), solid(1), solid(1), solid(1), solid(1), solid(1)});
    for (uint32_t bar = 0; bar < 8; bar++)
        video_palette(bar, 1, colors[bar]);
    for (uint32_t y = 0; y < VIDEO_MAP_H; y++)
        for (uint32_t x = 0; x < VIDEO_MAP_W; x++) {
            uint32_t bar = x / 5;
            if (bar > 7)
                bar = 7;
            video_map(x, y, 0, bar);
        }

    VIDEO->CTRL = VIDEO_CTRL_EN;
    io_dir(PIN_LED8, IO_OUTPUT);
    tohost = 1;

    int led = 0;
    for (;;) {
        led = !led;
        io_write(PIN_LED8, led);
        delay_ms(status & 1 ? 500 : 167);
    }
}
