"""显示面板显存, 并保存 RGB565 截图。"""

import struct
import tkinter as tk
import zlib

W, H = 240, 320


def rgb565(data):
    return bytes(
        c
        for (p,) in struct.iter_unpack('<H', data)
        for c in (((p >> 11) * 255 // 31), ((p >> 5 & 63) * 255 // 63), ((p & 31) * 255 // 31))
    )


def save_png(frame, path):
    rgb = rgb565(frame.read_bytes())

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    rows = b''.join(b'\0' + rgb[y * W * 3 : (y + 1) * W * 3] for y in range(H))
    path.write_bytes(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>2I5B', W, H, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(rows))
        + chunk(b'IEND', b'')
    )


def send(keys, char):
    if char:
        with keys.open('ab') as f:
            f.write(char.encode())


def show(frame, keys, process):
    root = tk.Tk()
    root.title(f'AMa sim — {frame.stem}')
    label = tk.Label(root)
    label.pack()
    # 按下的字符交给仿真里的 uart_tx, 相当于在串口终端里打字
    root.bind('<Key>', lambda e: send(keys, e.char))

    def refresh():
        if process.poll() is not None:
            root.destroy()
            return
        data = frame.read_bytes()
        # 写入期间可能读到半帧, 留到下一次刷新。
        if len(data) == W * H * 2:
            ppm = f'P6\n{W} {H}\n255\n'.encode() + rgb565(data)
            label.image = tk.PhotoImage(data=ppm, format='PPM').zoom(2)
            label.configure(image=label.image)
        root.after(100, refresh)

    root.after(0, refresh)
    root.mainloop()
