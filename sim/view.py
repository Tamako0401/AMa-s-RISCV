"""显示仿真里的屏幕 (LCD) 和 HDMI 画面, 并保存 RGB565 截图。"""

import struct
import tkinter as tk
import zlib

# 名字: (宽, 高, 窗口里放大几倍); 画面文件由 st7789_model (+frame) 和 video_sink (+video) 写
SCREENS = {'lcd': (240, 320, 2), 'hdmi': (640, 480, 1)}


def rgb565(data):
    return bytes(
        c
        for (p,) in struct.iter_unpack('<H', data)
        for c in (((p >> 11) * 255 // 31), ((p >> 5 & 63) * 255 // 63), ((p & 31) * 255 // 31))
    )


def save_png(frame, path, w, h):
    rgb = rgb565(frame.read_bytes())

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    rows = b''.join(b'\0' + rgb[y * w * 3 : (y + 1) * w * 3] for y in range(h))
    path.write_bytes(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>2I5B', w, h, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(rows))
        + chunk(b'IEND', b'')
    )


def send(keys, char):
    if char:
        with keys.open('ab') as f:
            f.write(char.encode())


def show(frames, keys, process):
    root = tk.Tk()
    root.title(f'AMa sim — {next(iter(frames.values())).stem}')
    labels = {}
    for name in frames:
        labels[name] = tk.Label(root)
        labels[name].pack(side='left', anchor='n')
    # 按下的字符交给仿真里的 uart_tx, 相当于在串口终端里打字
    root.bind('<Key>', lambda e: send(keys, e.char))

    def refresh():
        if process.poll() is not None:
            root.destroy()
            return
        for name, frame in frames.items():
            w, h, zoom = SCREENS[name]
            data = frame.read_bytes()
            # 写入期间可能读到半帧, 留到下一次刷新。
            if len(data) == w * h * 2:
                ppm = f'P6\n{w} {h}\n255\n'.encode() + rgb565(data)
                labels[name].image = tk.PhotoImage(data=ppm, format='PPM').zoom(zoom)
                labels[name].configure(image=labels[name].image)
        root.after(100, refresh)

    root.after(0, refresh)
    root.mainloop()
