/* 在 C 中模拟 SPI 卡的字节响应, 编译/运行未改的 sd.c。 */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "sd.h"
static int selected, fast, power_clocks, pos, head, tail, version, capacity, fault, tries, reads;
static uint8_t command[6], queue[1024];
static uint32_t ticks, address;
static int fail_trailing;
void board_sd_init(void)
{
    selected = 0;
}
void board_sd_speed(int f)
{
    fast = f;
}
void board_sd_select(int on)
{
    selected = on;
    if (!on)
        pos = head = tail = 0;
}
uint32_t bsp_cycles(void)
{
    return ticks += 50000;
}
void delay_ms(uint32_t ms)
{
    ticks += ms * 50000;
}
static void push(int b)
{
    assert(tail < 1024);
    queue[tail++] = (uint8_t)b;
}
static void respond(void)
{
    uint32_t arg = (uint32_t)command[1] << 24 | (uint32_t)command[2] << 16 | (uint32_t)command[3] << 8 | command[4];
    int cmd = command[0] & 63;
    if (fault == 1)
        return; /* 完全没插卡 */
    switch (cmd) {
    case 0:
        assert(!fast && power_clocks >= 80 && command[5] == 0x95);
        push(1);
        break;
    case 8:
        assert(command[5] == 0x87 && arg == 0x1aa);
        if (!version) {
            push(5);
            break;
        }
        push(1);
        push(0);
        push(0);
        push(1);
        push(fault == 2 ? 0xab : 0xaa);
        break;
    case 55:
        push(1);
        break;
    case 41:
        assert(arg == (version ? 0x40000000u : 0));
        push(fault == 3 || tries++ < 2 ? 1 : 0);
        break;
    case 58:
        fail_trailing = fault == 7;
        push(0);
        push(0x80 | (capacity ? 0x40 : 0));
        push(0xff);
        push(0x80);
        push(0);
        break;
    case 16:
        assert(!capacity && arg == 512);
        push(0);
        break;
    case 17:
        assert(fast);
        address = arg;
        reads++;
        push(0);
        if (fault == 4)
            break; /* token 超时 */
        push(255);
        push(fault == 5 ? 0x0b : 0xfe);
        for (int i = 0; i < 512; i++)
            push(i);
        push(255);
        push(255);
        break;
    default:
        assert(0);
    }
}
int board_sd_xfer(uint8_t v, uint8_t *r)
{
    ticks += 10000;
    if (fault == 6 || (fail_trailing && !selected))
        return 0;
    *r = 255;
    if (!selected) {
        power_clocks += 8;
        return 1;
    }
    if (head < tail) {
        *r = queue[head++];
        return 1;
    }
    if (pos || (v & 0xc0) == 0x40) {
        command[pos++] = v;
        if (pos == 6) {
            pos = head = tail = 0;
            respond();
        }
    }
    return 1;
}
static void reset(int ver, int hc, int err)
{
    selected = fast = power_clocks = pos = head = tail = tries = reads = ticks = 0;
    fail_trailing = 0;
    version = ver;
    capacity = hc;
    fault = err;
}
int main(void)
{
    uint8_t data[512];
    for (int card = 0; card < 3; card++) {
        reset(card != 0, card == 2, 0);
        assert(sd_init() == (card == 2 ? 2 : 1));
        assert(fast && !selected);
        assert(sd_read_block(123, data));
        assert(address == (card == 2 ? 123u : 123u * 512));
        for (int i = 0; i < 512; i++)
            assert(data[i] == (uint8_t)i);
        assert(!selected && reads == 1);
        for (int err = 4; err <= 6; err++) {
            fault = err;
            assert(!sd_read_block(123, data));
            assert(!selected);
        }
    }
    for (int err = 1; err <= 3; err++) {
        reset(1, 1, err);
        assert(sd_init() == 0 && !selected);
    }
    reset(1, 1, 7);
    assert(sd_init() == 0 && !selected);
    puts("SD protocol: SDv1/SDSCv2/SDHC, byte/block addresses, CRC/echo, retries, token/SPI timeouts passed");
    return 0;
}
