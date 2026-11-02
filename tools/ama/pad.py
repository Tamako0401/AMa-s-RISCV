"""ama monitor --pad: 开一个小窗口当手柄, 60 帧/秒把真正的按键状态 (按住 / 松开) 和鼠标经串口发给板子,
同时在终端显示串口输出。帧的格式见 game/board/link.h ('P' 帧) 和 pad.h; 键位同串口终端 (wasd / 方向键, Shift 慢速, j / 空格 = A ...)。
插着的手柄 (Xbox 布局, 见 xpad.py) 和键盘合在一起发。
鼠标在窗口里时一直发它的位置 (就是画面位置, 640x360) 和左右键; 板上用不用鼠标看暂停菜单里的输入方式 (game/board/menu.h)。"""

import sys
import threading
import tkinter as tk

from .xpad import Gamepad

W, H = 640, 360
UP, DOWN, LEFT, RIGHT, A, B, SLOW = 1, 2, 4, 8, 16, 32, 64
KEYS = {
    'w': UP,
    'Up': UP,
    's': DOWN,
    'Down': DOWN,
    'a': LEFT,
    'Left': LEFT,
    'd': RIGHT,
    'Right': RIGHT,
    'j': A,
    'space': A,
    'Return': A,
    'z': A,
    'k': B,
    'x': B,
    'Shift_L': SLOW,
    'Shift_R': SLOW,
}
BUTTONS = {'r': 1, 'q': 2, 'm': 2, 'Escape': 2}  # btn 的 bit0 重开, bit1 MENU
RELEASE_MS = 30  # X11 的自动连发是 "松开 + 按下" 成对来的: 松开后这么久没再按下才算真的松开


def frame(kind, data):
    """game/board/link.h 的帧: [0xFF] [类型] [长度] [数据] [校验], 0xFF 之后每个字节都 < 0x80"""
    body = [ord(kind), len(data), *data]
    return bytes([0xFF, *body, sum(body) & 127])


def run(ser):
    root = tk.Tk()
    root.title('ama pad')
    canvas = tk.Canvas(root, width=W, height=H, bg='#101018', highlightthickness=0)
    canvas.pack()
    canvas.create_text(
        W // 2,
        H // 2,
        fill='#c0c0c0',
        justify='center',
        text='焦点在这个窗口时按键发给板子\n\nwasd / 方向键 移动, Shift 慢速\nj / 空格 / 回车 = A (bomb、出刀、确定)\n'
        'r 重开, m / q / Esc 暂停菜单 (在里面切换输入方式: 按键 / 指点)\n'
        '鼠标在窗口里 = 画面位置, 左键 = A, 右键 = B (指点方式下才管用)\n\n串口输出在终端里',
    )
    state = {'keys': 0, 'btn': 0, 'inside': False, 'click': False, 'right': False, 'x': 0, 'y': 0}
    pending = {}  # 等着确认的松开
    down = set()  # 按着的键 (自动连发的 "按下" 不算新按)

    def name(e):
        return e.keysym if e.keysym in KEYS or e.keysym in BUTTONS else e.keysym.lower()

    def press(e):
        k = name(e)
        if k in pending:
            root.after_cancel(pending.pop(k))
        down.add(k)
        state['keys'] |= KEYS.get(k, 0)
        state['btn'] |= BUTTONS.get(k, 0)

    def release(e):
        k = name(e)

        def really():
            pending.pop(k, None)
            down.discard(k)
            state['keys'] &= ~KEYS.get(k, 0)
            state['btn'] &= ~BUTTONS.get(k, 0)

        if k in pending:
            root.after_cancel(pending.pop(k))
        pending[k] = root.after(RELEASE_MS, really)

    def motion(e):
        state['x'] = min(max(e.x, 0), W - 1)
        state['y'] = min(max(e.y, 0), H - 1)

    root.bind('<KeyPress>', press)
    root.bind('<KeyRelease>', release)
    canvas.bind('<Motion>', motion)
    canvas.bind('<Enter>', lambda e: state.update(inside=True))
    canvas.bind('<Leave>', lambda e: state.update(inside=False))
    canvas.bind('<ButtonPress-1>', lambda e: state.update(click=True))
    canvas.bind('<ButtonRelease-1>', lambda e: state.update(click=False))
    canvas.bind('<ButtonPress-3>', lambda e: state.update(right=True))
    canvas.bind('<ButtonRelease-3>', lambda e: state.update(right=False))

    gamepad = Gamepad()

    def tick():
        mouse = state['inside']
        pad_keys, pad_btn = gamepad.poll()
        btn = (
            state['btn']
            | pad_btn
            | (4 if mouse else 0)
            | (8 if mouse and state['click'] else 0)
            | (16 if mouse and state['right'] else 0)
        )
        x, y = state['x'], state['y']
        ser.write(frame('P', [state['keys'] | pad_keys, btn, x >> 7, x & 127, y >> 7, y & 127]))
        root.after(16, tick)

    def reader():
        while True:
            try:
                data = ser.read(ser.in_waiting or 1)
            except Exception:
                return
            sys.stdout.write(data.decode('utf-8', 'replace'))
            sys.stdout.flush()

    threading.Thread(target=reader, daemon=True).start()
    tick()
    root.focus_force()
    try:
        root.mainloop()
    except KeyboardInterrupt:
        pass
