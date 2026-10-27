/* 板上的输入: 串口收按键, 两种来源都认, 不用切换:
 *   1. 串口终端 (ama monitor): 键盘打的字直接转发过来。wasd / 方向键移动, 大写 WASD (按住 Shift) 慢速,
 *      j / 空格 / 回车 = A, k = B, r = 重开, q = 回标题。
 *      终端只发 "按下" 和按住后的自动连发, 不发 "松开": 收到一个键就当它按住了 PAD_HOLD 帧, 连发会一直续上。
 *      所以刚按下的第一下只走一小段, 之后要等系统的连发延迟 (约半秒) 才连续走; 可以调短: xset r rate 150 40。
 *   2. ama monitor --pad (tools/ama/pad.py): 电脑上开个小窗口, 60 帧/秒发真正的按键状态和鼠标位置
 *      (6 字节一包, 第一字节最高位为 1):
 *      [0x80 | keys]  [btn]  [x 高 7 位] [x 低 7 位] [y 高 7 位] [y 低 7 位]
 *      keys = PAD_UP..PAD_SLOW (低 7 位); btn: bit0 R, bit1 Q, bit2 鼠标在窗口里, bit3 鼠标左键; x, y 是 640x360
 * 画面坐标。 */
#ifndef PAD_H
#define PAD_H

#include <stdint.h>

#define PAD_UP 0x01
#define PAD_DOWN 0x02
#define PAD_LEFT 0x04
#define PAD_RIGHT 0x08
#define PAD_A 0x10 /* 东方: bomb; 水果: 出刀; 标题: 确定 */
#define PAD_B 0x20
#define PAD_SLOW 0x40 /* 东方: 慢速 (Shift) */
#define PAD_RESTART 0x80
#define PAD_MENU 0x100
#define PAD_CLICK 0x200 /* 鼠标左键 */

#define PAD_HOLD 6 /* 终端来的键当作按住几帧 (自动连发约 30 次/秒, 6 帧 = 100 ms 续得上) */

typedef struct {
    uint32_t held;    /* 现在按着的 */
    uint32_t pressed; /* 这一帧刚按下的 */
    uint8_t mouse;    /* 鼠标在 pad.py 的窗口里, mx, my 有意义 */
    int32_t mx, my;   /* 画面坐标 (640x360) */
    /* 内部 */
    uint8_t ttl[10]; /* 终端来的键还算按住几帧 */
    uint32_t pad_keys, last;
    uint8_t esc, packet[6], packet_n;
} pad_t;

/* 每帧调一次: 读完串口里攒下的字节, 更新 held / pressed */
void pad_poll(pad_t *pad);

#endif
