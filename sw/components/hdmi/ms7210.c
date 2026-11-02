#include "ms7210.h"
#include "bsp.h"

#define DEV 0xB2 /* SA 脚上拉 (MES50HP 硬件手册 3.3.2) */

/* 每次读写后等 1 ms, 同盘古例程 (iic_dri.v 的 T_WR) */
static int reg_write(const i2c_pins_t *i2c, uint16_t reg, uint8_t value)
{
    int err = i2c_write_reg16(i2c, DEV, reg, value);
    delay_ms(1);
    return err;
}

static int reg_read(const i2c_pins_t *i2c, uint16_t reg, uint8_t *value)
{
    int err = i2c_read_reg16(i2c, DEV, reg, value);
    delay_ms(1);
    return err;
}

/* 读改写: 只改 mask 里的位 */
static int reg_update(const i2c_pins_t *i2c, uint16_t reg, uint8_t mask, uint8_t value)
{
    uint8_t old;
    if (reg_read(i2c, reg, &old))
        return -1;
    return reg_write(i2c, reg, (uint8_t)((old & ~mask) | value));
}

/* 寄存器表抄自盘古 50K 例程 05_hdmi_test/src/ms7210_ctl.v (RGB888 输入, 自动识别分辨率);
 * 两段之间要等约 0.3 秒, 同例程。第二段在放开发送部分复位 (0x000B = 0x11) 处拆成两张表, 中间插音频设置。 */
static const uint16_t init_seq[][2] = {
    {0x1281, 0x04}, {0x0016, 0x04}, {0x0009, 0x01}, {0x0007, 0x09}, {0x0008, 0xF0}, {0x000A, 0xF0}, {0x0006, 0x11},
    {0x0531, 0x84}, {0x0900, 0x20}, {0x0901, 0x47}, {0x0904, 0x09}, {0x0923, 0x07}, {0x0924, 0x44}, {0x0925, 0x44},
    {0x090F, 0x80}, {0x091F, 0x07}, {0x0920, 0x1E}, {0x0018, 0x20}, {0x05C0, 0xFE},
};
static const uint16_t setting_seq[][2] = {
    {0x000B, 0x00}, {0x0507, 0x06}, {0x0906, 0x04}, {0x0920, 0x5E}, {0x0926, 0xDD},
    {0x0927, 0x0D}, {0x0928, 0x88}, {0x0929, 0x08}, {0x0910, 0x01},
};
static const uint16_t release_seq[][2] = {
    {0x000B, 0x11}, {0x050E, 0x00}, {0x050A, 0x82}, {0x0509, 0x02}, {0x050B, 0x0D}, {0x050D, 0x06}, {0x050D, 0x11},
    {0x050D, 0x58}, {0x050D, 0x00}, {0x050D, 0x00}, {0x050D, 0x00}, {0x050D, 0x00}, {0x050D, 0x00}, {0x050D, 0x00},
    {0x050D, 0x00}, {0x050D, 0x00}, {0x050D, 0x00}, {0x050D, 0x00}, {0x050D, 0x00}, {0x050E, 0x40}, {0x0507, 0x00},
};

/* 音频从 I2S 脚进 (mes2l100hp: audio 外设直连, 48 kHz 双声道)。位的含义按 GitHub
 * avmwww/ms7210-linux-driver (GPL-2, 只参考寄存器、没抄代码), 没有官方寄存器手册核对过。
 * 厂商表已开音频时钟、48 kHz 档 (0x0531)、音频时钟取管脚 (0x0008)、最后解除静音 (0x0507), 这里补其余几项;
 * 同驱动的顺序, 在发送部分复位期间写。每项 {寄存器, 要改的位, 值}。 */
static const uint16_t audio_seq[][3] = {
    {0x0503, 0x01, 0x00}, /* HDMI 模式 (1 = DVI, 不带声音) */
    {0x00A5, 0x18, 0x00}, /* 音频脚用作 I2S, 不是 S/PDIF */
    {0x0048, 0x0F, 0x00}, /* 驱动 shell_init 里的 "audio" */
    {0x0570, 0x01, 0x01}, /* 音量直通, 不经音量控制 */
    {0x0530, 0x01, 0x00}, /* 普通音频采样包, 不是 HBR */
    {0x0532, 0x0F, 0x01}, /* 只开 I2S0 一路 = 2 声道 */
    {0x0535, 0x30, 0x10}, /* 16 位 I2S, 同公开驱动 audio_bits=0 */
};
/* 音频 InfoFrame (类型 0x84、版本 1、长度 10) 的内容: 校验和, LPCM 双声道, 48 kHz / 16 位, 喇叭分配 0 = 前左前右 */
static const uint8_t audio_infoframe[] = {0x53, 0x11, 0x0D, 0, 0, 0, 0, 0, 0, 0, 0};

static int write_all(const i2c_pins_t *i2c, const uint16_t (*seq)[2], uint32_t n)
{
    for (uint32_t i = 0; i < n; i++)
        if (reg_write(i2c, seq[i][0], seq[i][1]))
            return -1;
    return 0;
}

int ms7210_init(const i2c_pins_t *i2c)
{
    /* 先写一个寄存器再读回, 确认芯片在 */
    uint8_t id = 0;
    if (reg_write(i2c, 0x0003, 0x5A) || reg_read(i2c, 0x0003, &id) || id != 0x5A)
        return -1;
    if (write_all(i2c, init_seq, sizeof init_seq / sizeof init_seq[0]))
        return -1;
    delay_ms(300);
    if (write_all(i2c, setting_seq, sizeof setting_seq / sizeof setting_seq[0]))
        return -1;
    /* 音频这几项出错也照样往下放开复位, 别让画面跟着没了, 最后再报错 (所以用 | 不用 ||) */
    int audio_err = 0;
    for (uint32_t i = 0; i < sizeof audio_seq / sizeof audio_seq[0]; i++)
        audio_err |= reg_update(i2c, audio_seq[i][0], (uint8_t)audio_seq[i][1], (uint8_t)audio_seq[i][2]);
    if (write_all(i2c, release_seq, sizeof release_seq / sizeof release_seq[0]))
        return -1;
    /* 音频 InfoFrame: 先关 0x050E bit5, 写完再开 = 告诉芯片包备好了 (bit6 是上面 AVI 的, 不动) */
    /* I2C 是有顺序的副作用, 不能用 | 把调用串在同一表达式里 (C 不保证操作数求值顺序)。 */
    audio_err |= reg_update(i2c, 0x050E, 0x20, 0x00);
    audio_err |= reg_write(i2c, 0x050A, 0x84);
    audio_err |= reg_write(i2c, 0x0509, 0x01);
    audio_err |= reg_write(i2c, 0x050B, 0x0A);
    for (uint32_t i = 0; i < sizeof audio_infoframe; i++)
        audio_err |= reg_write(i2c, 0x050D, audio_infoframe[i]);
    audio_err |= reg_update(i2c, 0x050E, 0x20, 0x20);
    return audio_err ? -1 : 0;
}
