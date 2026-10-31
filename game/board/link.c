#include "link.h"

int link_byte(link_t *link, uint8_t c)
{
    if (c == 0xFF) { /* 帧头: 不管之前收到哪, 从头开始 */
        link->stage = 1;
        return LINK_NONE;
    }
    if (link->stage == 0)
        return c & 0x80 ? LINK_NONE : LINK_TEXT;
    if (c & 0x80) { /* 帧里不该有 0x80 以上的字节: 坏了, 丢掉 */
        link->stage = 0;
        return LINK_NONE;
    }
    switch (link->stage) {
    case 1:
        link->frame.type = c;
        link->sum = c;
        link->stage = 2;
        break;
    case 2:
        if (c > LINK_MAX) {
            link->stage = 0;
            break;
        }
        link->frame.len = c;
        link->sum += c;
        link->n = 0;
        link->stage = 3;
        break;
    default:
        if (link->n < link->frame.len) {
            link->frame.data[link->n++] = c;
            link->sum += c;
            break;
        }
        link->stage = 0;
        return (link->sum & 127) == c ? LINK_FRAME : LINK_NONE;
    }
    return LINK_NONE;
}
