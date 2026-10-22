#ifndef HAND_UDP_H
#define HAND_UDP_H

#include <stdint.h>
#include "hand.h"

int hand_udp_open(int port); /* 成功返回 0 */
/* 收到新结果返回 1 并填 raw; 收齐了一张小图时 *image 指向它 (160x120 BGR), 否则不动 *image */
int hand_udp_poll(hand_raw_t *raw, const uint8_t **image);

#endif
