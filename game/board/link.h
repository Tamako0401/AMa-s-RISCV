/* 串口上的字节流: 终端打的字和程序发的帧混在一条线上, 这里把它们拆开 (不认识具体的帧, 只管拆)。
 *
 *   小于 0x80 的字节: 终端打的字 (ama monitor 里按 w 就是 'w')
 *   帧: [0xFF] [类型] [长度 n] [数据 x n] [校验]
 *     - 键盘打不出 0xFF, 看到它就是一帧开始; 之后的字节都小于 0x80, 所以数据不会被当成新的帧头,
 *       中途断了 (掉字节、插进打的字) 也会在下一个 0xFF 重新对上。
 *     - 每个字节只用低 7 位: 大于 127 的数拆成高 7 位、低 7 位两个字节 (最大 16383), 见 link_u14。
 *     - 校验 = (类型 + 长度 + 各数据字节) & 127, 不对整帧丢掉。n 最大 LINK_MAX。
 *   类型 (一个可见字符, 好认):
 *     'P' 手柄 (tools/ama/pad.py, 见 pad.h)
 *     以后的设备另起一个字母。
 * 发帧的一方: 定时发完整状态 (按着哪些键、手在哪), 不发 "按下了 / 松开了" 这种事件, 丢一帧也不要紧。 */
#ifndef LINK_H
#define LINK_H

#include <stdint.h>

#define LINK_MAX 16

typedef struct {
    uint8_t type, len;
    uint8_t data[LINK_MAX];
} link_frame_t;

typedef struct {
    uint8_t stage; /* 0 不在帧里; 1 等类型; 2 等长度; 3 收数据 (收完下一个是校验) */
    uint8_t n, sum;
    link_frame_t frame;
} link_t;

enum { LINK_NONE, LINK_TEXT, LINK_FRAME };

/* 喂一个字节。返回 LINK_TEXT: 是打的字; LINK_FRAME: 一帧收齐, 在 link->frame; LINK_NONE: 帧的一部分或坏字节 */
int link_byte(link_t *link, uint8_t c);

/* 两个 7 位字节拼回一个数 (高位在前) */
static inline uint32_t link_u14(const uint8_t *p)
{
    return (uint32_t)p[0] << 7 | p[1];
}

#endif
