/* 板上的输入: 串口收按键和鼠标, 两种发法都认 (用哪些来控制游戏由暂停菜单的输入方式决定, 见 menu.h)。
 * 两个串口都收, 处理方法一样: 控制台串口 (CONSOLE_UART) 和第二个串口 (AUX_UART, bsp/aux_uart.h; mes2l100hp 上接
 * WS63 星闪, 50K 手柄板经它发 'P' 帧)。每个口各有一个帧解析器, 各口 'P' 帧的按键合起来 (按住任一口的键就算按着);
 * 一个口 PAD_STALE 帧没来 'P' 帧, 它的按键和鼠标就作废 (发的一方断了不会一直按着)。
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

#define PAD_HOLD 6   /* 终端来的键当作按住几帧 (自动连发约 30 次/秒, 6 帧 = 100 ms 续得上) */
#define PAD_STALE 30 /* 一个口这么多帧 (0.5 秒) 没来 'P' 帧, 它的按键作废; 发的一方 60 帧/秒 */
#define PAD_PORTS 2  /* 字节源: 0 = 控制台串口, 1 = 第二个串口 */

/* 一个字节源的状态 (内部) */
typedef struct {
    uint8_t esc;   /* 收到 ESC 后: 1 等 '[', 2 等方向字母 */
    uint8_t quiet; /* 这一帧还没收到字节 (单按 Esc 的判断) */
    uint8_t mouse; /* 最后一个 'P' 帧: 鼠标在窗口里 */
    uint8_t age;   /* 最后一个 'P' 帧是几帧前收到的, 到 PAD_STALE 不再加 */
    uint32_t keys; /* 最后一个 'P' 帧的按键 */
    link_t link;
} pad_port_t;

typedef struct {
    uint32_t held;    /* 现在按着的 */
    uint32_t pressed; /* 这一帧刚按下的 */
    uint8_t mouse;    /* 鼠标在 pad.py 的窗口里, mx, my 有意义 */
    int32_t mx, my;   /* 画面坐标 (640x360) */
    /* 内部 */
    uint8_t ttl[10];         /* 终端来的键还算按住几帧 */
    uint32_t pad_keys, last; /* pad_keys: 各口 'P' 帧的按键合起来 */
    /* 'P' 以外的帧 (以后的设备另起一个字母, 见 link.h) 交给它; 不设就丢掉 */
    void (*on_frame)(const link_frame_t *frame, void *ctx);
    void *ctx;
    /* 内部 */
    pad_port_t port[PAD_PORTS];
} pad_t;

/* 每帧调一次: 读完两个串口里攒下的字节, 更新 held / pressed。等于 pad_begin + 每个字节 pad_byte + pad_end */
void pad_poll(pad_t *pad);

/* pad_poll 拆开的三步, 给电脑上的测试 (sw/app/game/test) 和别的字节源用。port: 0 ~ PAD_PORTS-1 */
void pad_begin(pad_t *pad);
void pad_byte(pad_t *pad, uint32_t port, uint8_t c);
void pad_end(pad_t *pad);

#endif
