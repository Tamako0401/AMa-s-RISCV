#include "sd.h"
#include "board_sd.h"

static int high_capacity, failed;
static uint8_t xfer(uint8_t v)
{
    if (failed)
        return 255;
    uint8_t r = 255;
    if (!board_sd_xfer(v, &r))
        failed = 1;
    return r;
}
static void release(void)
{
    board_sd_select(0);
    xfer(255);
}
static uint8_t command(int cmd, uint32_t arg)
{
    release();
    board_sd_select(1);
    xfer(255);
    xfer((uint8_t)(0x40 | cmd));
    for (int n = 24; n >= 0; n -= 8)
        xfer((uint8_t)(arg >> n));
    xfer(cmd == 0 ? 0x95 : cmd == 8 ? 0x87 : 1);
    for (int n = 0; n < 16; n++) {
        uint8_t r = xfer(255);
        if (!(r & 128))
            return r;
    }
    return 255;
}
int sd_init(void)
{
    failed = high_capacity = 0;
    board_sd_init();
    board_sd_speed(0);
    delay_ms(2);
    for (int i = 0; i < 10; i++)
        xfer(255);
    int ok = 0, v2;
    if (command(0, 0) != 1)
        goto done;
    uint8_t r = command(8, 0x1aa);
    v2 = r == 1;
    if (v2) {
        xfer(255);
        xfer(255);
        if (xfer(255) != 1 || xfer(255) != 0xaa)
            goto done;
    } else if (r != 5)
        goto done;
    uint32_t start = bsp_cycles();
    do {
        if (command(55, 0) > 1)
            goto done;
        r = command(41, v2 ? 0x40000000 : 0);
        if (!r)
            break;
        if (r != 1 || failed || bsp_cycles() - start > SYSCLK_HZ * 2)
            goto done;
    } while (1);
    if (command(58, 0))
        goto done;
    r = xfer(255);
    high_capacity = v2 && (r & 0x40);
    xfer(255);
    xfer(255);
    xfer(255);
    if (!(r & 0x80))
        goto done;
    if (!high_capacity && command(16, 512))
        goto done;
    ok = !failed;
done:
    release();
    ok = ok && !failed;
    if (ok)
        board_sd_speed(1);
    return ok ? (high_capacity ? 2 : 1) : 0;
}
int sd_read_block(uint32_t lba, uint8_t data[512])
{
    failed = 0;
    int ok = 0;
    if (!high_capacity && lba > 0x7fffff)
        return 0;
    if (command(17, high_capacity ? lba : lba << 9))
        goto done;
    uint32_t start = bsp_cycles();
    uint8_t r;
    do {
        r = xfer(255);
        if (failed || bsp_cycles() - start > SYSCLK_HZ / 4)
            goto done;
    } while (r == 255);
    if (r != 0xfe)
        goto done;
    for (int i = 0; i < 512; i++)
        data[i] = xfer(255);
    xfer(255);
    xfer(255); /* CRC (SPI 模式未启用 CRC) */
    ok = !failed;
done:
    release();
    return ok && !failed;
}
