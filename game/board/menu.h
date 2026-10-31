/* 暂停菜单: 按 MENU (终端 m / q / Esc, pad.py 窗口里 m / q / Esc, 以后 GameShield 的 MENU 键) 打开。
 * 游戏停住、画面变暗, 中间写菜单和调试信息。上下选, A 确定, 左右 / A 改输入方式, 再按 MENU 回到游戏。
 *
 * 输入方式: 同一时间只有一种来源控制游戏, 只在这里切换, 不会自己变。
 *   按键: 方向键移动, A / B / 慢速 (键盘、pad.py、以后的 GameShield)。鼠标、手都不管。
 *   指点: 鼠标 (pad.py 窗口里) 或手势给位置, 左键 = A、右键 = B, 张开手放 bomb。方向键不管。
 * 重开 (RST) 和 MENU 是功能键, 哪种方式下都能用。 */
#ifndef MENU_H
#define MENU_H

#include <stdint.h>
#include "hand.h"
#include "pad.h"

enum { INPUT_KEYS, INPUT_POINT, INPUT_N };

enum { MENU_STAY, MENU_RESUME, MENU_TITLE }; /* menu_frame 的返回值 */

typedef struct {
    uint8_t item;    /* 光标在哪一项 */
    uint8_t in_game; /* 从游戏里打开的: 多一项 "回标题" */
} menu_t;

/* 调试信息: 菜单里显示 */
typedef struct {
    const hand_t *hand;
    uint32_t cpu; /* CPU 最近一帧用了多少拍 */
} menu_info_t;

void menu_open(menu_t *m, int in_game);
/* 每帧调一次: 处理按键、写菜单文字; *mode 是现在的输入方式, 菜单里改了就改它 */
int menu_frame(menu_t *m, const pad_t *pad, uint8_t *mode, const menu_info_t *info);
/* 关菜单: 擦掉菜单占的文字 */
void menu_close(void);

/* 输入方式的名字 ("keys" / "point") */
const char *menu_input_name(uint8_t mode);

#endif
