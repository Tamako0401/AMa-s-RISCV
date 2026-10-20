#include "i2c.h"
#include "io.h"

static uint32_t cycles(void)
{
    uint32_t c;
    __asm__ volatile("csrr %0, cycle" : "=r"(c));
    return c;
}

static void wait_half(const i2c_pins_t *p)
{
    uint32_t start = cycles();
    while (cycles() - start < p->half_cycles)
        ;
}

static void sda_out(const i2c_pins_t *p, int level)
{
    io_write(p->sda, level);
    io_dir(p->sda, IO_OUTPUT);
}

static void sda_release(const i2c_pins_t *p)
{
    io_dir(p->sda, IO_INPUT);
}

void i2c_init(const i2c_pins_t *p)
{
    io_write(p->scl, 1);
    io_dir(p->scl, IO_OUTPUT);
    sda_out(p, 1);
}

static void start(const i2c_pins_t *p)
{
    sda_out(p, 1);
    io_write(p->scl, 1);
    wait_half(p);
    sda_out(p, 0);
    wait_half(p);
    io_write(p->scl, 0);
}

static void stop(const i2c_pins_t *p)
{
    sda_out(p, 0);
    wait_half(p);
    io_write(p->scl, 1);
    wait_half(p);
    sda_out(p, 1);
    wait_half(p);
}

/* 返回 0 = 收到 ACK */
static int write_byte(const i2c_pins_t *p, uint8_t byte)
{
    for (int i = 7; i >= 0; i--) {
        sda_out(p, byte >> i & 1);
        wait_half(p);
        io_write(p->scl, 1);
        wait_half(p);
        io_write(p->scl, 0);
    }
    sda_release(p);
    wait_half(p);
    io_write(p->scl, 1);
    wait_half(p);
    int nack = io_read(p->sda);
    io_write(p->scl, 0);
    return nack ? -1 : 0;
}

/* 读一个字节后回 NACK (只读一个字节) */
static uint8_t read_byte(const i2c_pins_t *p)
{
    uint8_t byte = 0;
    sda_release(p);
    for (int i = 0; i < 8; i++) {
        wait_half(p);
        io_write(p->scl, 1);
        wait_half(p);
        byte = byte << 1 | io_read(p->sda);
        io_write(p->scl, 0);
    }
    sda_out(p, 1);
    wait_half(p);
    io_write(p->scl, 1);
    wait_half(p);
    io_write(p->scl, 0);
    return byte;
}

static int write_addr(const i2c_pins_t *p, uint8_t dev, uint16_t reg)
{
    start(p);
    return write_byte(p, dev) || write_byte(p, reg >> 8) || write_byte(p, reg & 0xFF) ? -1 : 0;
}

int i2c_write_reg16(const i2c_pins_t *p, uint8_t dev, uint16_t reg, uint8_t value)
{
    int err = write_addr(p, dev, reg) || write_byte(p, value) ? -1 : 0;
    stop(p);
    return err;
}

int i2c_read_reg16(const i2c_pins_t *p, uint8_t dev, uint16_t reg, uint8_t *value)
{
    int err = write_addr(p, dev, reg);
    if (!err) {
        start(p); /* 重复起始, 再发读地址 */
        err = write_byte(p, dev | 1);
        if (!err)
            *value = read_byte(p);
    }
    stop(p);
    return err;
}
