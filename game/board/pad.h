/* 板上的输入: 串口收按键和鼠标, 两种发法都认 (用哪些来控制游戏由暂停菜单的输入方式决定, 见 menu.h):
 *   1. 串口终端 (ama monitor): 键盘打的字直接转发过来。wasd / 方向键移动, 大写 WASD (按住 Shift) 慢速,
 *      j / 空格 / 回车 = A, k = B, r = 重开, m / q / Esc = MENU (暂停菜单)。
 *      终端只发 "按下" 和按住后的自动连发, 不发 "松开": 收到一个键就当它按住了 PAD_HOLD 帧, 连发会一直续上。
 *      所以刚按下的第一下只走一小段, 之后要等系统的连发延迟 (约半秒) 才连续走; 可以调短: xset r rate 150 40。
 *   2. ama monitor --pad (tools/ama/pad.py): 电脑上开个小窗口, 60 帧/秒发真正的按键状态和鼠标位置,
 *      是 link.h 的 'P' 帧, 6 个数据字节: [keys] [btn] [x 高 7 位] [x 低 7 位] [y 高 7 位] [y 低 7 位]
 *      keys = PAD_UP..PAD_SLOW; btn: bit0 R, bit1 Q, bit2 鼠标在窗口里, bit3 鼠标左键, bit4 鼠标右键;
 *      x, y 是 640x360 画面坐标。 */
#ifndef PAD_H
#define PAD_H

#include <stdint.h>
#include "link.h"

#define PAD_UP 0x01
#define PAD_DOWN 0x02
#define PAD_LEFT 0x04
#define PAD_RIGHT 0x08
#define PAD_A 0x10 /* 东方: bomb; 水果: 出刀; 标题、菜单: 确定 */
#define PAD_B 0x20
#define PAD_SLOW 0x40 /* 东方: 慢速 (Shift) */
#define PAD_RESTART 0x80
#define PAD_MENU 0x100   /* 暂停菜单 */
#define PAD_CLICK 0x200  /* 鼠标左键 (指点方式下 = A) */
#define PAD_RCLICK 0x400 /* 鼠标右键 (指点方式下 = B) */

#define PAD_HOLD 6 /* 终端来的键当作按住几帧 (自动连发约 30 次/秒, 6 帧 = 100 ms 续得上) */

typedef struct {
    uint32_t held;    /* 现在按着的 */
    uint32_t pressed; /* 这一帧刚按下的 */
    uint8_t mouse;    /* 鼠标在 pad.py 的窗口里, mx, my 有意义 */
    int32_t mx, my;   /* 画面坐标 (640x360) */
    /* 内部 */
    uint8_t ttl[10]; /* 终端来的键还算按住几帧 */
    uint32_t pad_keys, last;
    /* 'P' 以外的帧 (以后的设备另起一个字母, 见 link.h) 交给它; 不设就丢掉 */
    void (*on_frame)(const link_frame_t *frame, void *ctx);
    void *ctx;
    /* 内部 */
    uint8_t esc; /* 收到 ESC 后: 1 等 '[', 2 等方向字母 */
    link_t link;
} pad_t;

/* 每帧调一次: 读完串口里攒下的字节, 更新 held / pressed */
void pad_poll(pad_t *pad);

#endif
