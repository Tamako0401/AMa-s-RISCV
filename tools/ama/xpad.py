"""手柄 (Xbox 或 SDL 认得的其它手柄, 都按 Xbox 布局) -> pad.py 的按键位, 和键盘按的合在一起发给板子。
键位: 十字键 / 左摇杆 = 方向, A = A, B = B, LB / RB / 扳机 = 慢速, Start (≡) = MENU, Back (⧉) = 重开。
没装 pygame-ce 或没插手柄时什么都不做; 中途插拔、蓝牙断了重连也认 (收到插拔事件就重新打开)。"""

import os
import time

UP, DOWN, LEFT, RIGHT, A, B, SLOW = 1, 2, 4, 8, 16, 32, 64
RESTART, MENU = 1, 2  # 'P' 帧 btn 的 bit0, bit1
DEAD = 0.45  # 摇杆推过满量程的这么多才算按方向


class Gamepad:
    def __init__(self):
        self.pads = []
        self.count = -1  # < 0: 下次 poll 重新打开所有手柄
        try:
            os.environ.setdefault('SDL_VIDEODRIVER', 'dummy')  # 只要事件循环, 不开窗口 (窗口是 tkinter 的)
            os.environ['PYGAME_HIDE_SUPPORT_PROMPT'] = '1'
            import pygame
            from pygame._sdl2 import controller
        except ImportError:
            self.pg = None
            return
        pygame.display.init()
        controller.init()
        self.pg, self.ctl = pygame, controller

    def names(self):
        return [p.name for p in self.pads]

    def _rescan(self):
        self.pads = [self.ctl.Controller(i) for i in range(self.ctl.get_count()) if self.ctl.is_controller(i)]
        if self.pads:
            print(f'\r\n[pad] 手柄: {", ".join(self.names())}\r\n', end='')

    def poll(self):
        """返回 (keys, btn): 所有手柄按着的合在一起"""
        if not self.pg:
            return 0, 0
        pg = self.pg
        plug = (pg.CONTROLLERDEVICEADDED, pg.CONTROLLERDEVICEREMOVED, pg.JOYDEVICEADDED, pg.JOYDEVICEREMOVED)
        if any(e.type in plug for e in pg.event.get()) or self.count < 0:
            self.count = 0
            self._rescan()
        keys = btn = 0
        for p in self.pads:
            if not p.attached():
                continue
            try:
                keys, btn = _merge((keys, btn), _read(self.pg, p))
            except Exception:  # noqa: BLE001 - 拔掉的手柄读会出错, 下次重新数
                self.count = -1
        return keys, btn


def _merge(a, b):
    return a[0] | b[0], a[1] | b[1]


def _read(pg, p):
    def button(name):
        return p.get_button(getattr(pg, f'CONTROLLER_BUTTON_{name}'))

    def axis(name):
        return p.get_axis(getattr(pg, f'CONTROLLER_AXIS_{name}')) / 32767

    lx, ly = axis('LEFTX'), axis('LEFTY')
    keys = 0
    keys |= UP if button('DPAD_UP') or ly < -DEAD else 0
    keys |= DOWN if button('DPAD_DOWN') or ly > DEAD else 0
    keys |= LEFT if button('DPAD_LEFT') or lx < -DEAD else 0
    keys |= RIGHT if button('DPAD_RIGHT') or lx > DEAD else 0
    keys |= A if button('A') else 0
    keys |= B if button('B') else 0
    slow = button('LEFTSHOULDER') or button('RIGHTSHOULDER')
    slow = slow or axis('TRIGGERLEFT') > 0.5 or axis('TRIGGERRIGHT') > 0.5
    keys |= SLOW if slow else 0
    btn = (MENU if button('START') else 0) | (RESTART if button('BACK') else 0)
    return keys, btn


if __name__ == '__main__':  # 自测: uv run --with pygame-ce python -m ama.xpad (在 tools/ 下), 按键时打印对应的位
    names = {UP: '上', DOWN: '下', LEFT: '左', RIGHT: '右', A: 'A', B: 'B', SLOW: '慢'}
    gp, last = Gamepad(), None
    print('没装 pygame-ce' if not gp.pg else '等手柄... Ctrl+C 结束')
    while True:
        k, b = gp.poll()
        now = (
            [n for bit, n in names.items() if k & bit]
            + (['MENU'] if b & MENU else [])
            + (['重开'] if b & RESTART else [])
        )
        if now != last:
            print(' '.join(now) or '(松开)', flush=True)
            last = now
        time.sleep(1 / 60)
