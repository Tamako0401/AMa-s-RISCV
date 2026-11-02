/* 游戏从这里拿手。默认来源是板上 handnet (handnet.h): HDMI 输入的小图经硬件抓帧、推理。
 * 两个函数是弱符号: 调试时可以在本机附加的源文件里换成别的来源 (比如回放录好的结果), 见 ama.local.toml.example。 */
#ifndef HAND_SOURCE_H
#define HAND_SOURCE_H

#include <stdint.h>
#include "hand.h"
#include "handnet.h"
#include "pad.h"

extern handnet_t handnet; /* 板上 handnet 的统计 (菜单、侧栏显示) */

/* 开机调一次 */
void hand_source_init(pad_t *pad);
/* 每个游戏帧调一次; 有新结果时写 *raw 并返回 1。now_ms 是按帧数算的时刻 */
int hand_source(hand_raw_t *raw, uint32_t now_ms);

#endif
