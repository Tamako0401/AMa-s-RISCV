#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "opencv-python", "pyserial"]
# ///
"""从板子上取回 handnet 实际看到的 160x120 输入画面 (板上跑 sw/app/nn_grab), 存图并和电脑上的模型对比。

用法: ama run nn_grab 下载后关掉终端, 然后
    model/board_grab.py [--port /dev/ttyUSB0] [-n 张数] [--out 目录] [--every 秒]
每张存成 <out>/grab_<序号>.png (BGR, 可以直接看), 打印:
  - 板子自己的结果: 热力图概率 (0..255)、手心 (160x120)、握拳
  - 这张图在电脑上用 nnref (和板子逐位一致的整数模型, tests/nn/model.npz) 算的结果: 应当和板子完全一样
  - 每个通道的最小/平均/最大值: 电脑按 "有限范围" (16~235) 发 HDMI 时最小值在 16 附近、最大在 235 附近
用途: 判断板上识别差是不是因为输入画面和训练数据不一样 (颜色范围、亮度、对焦等)。
"""

import argparse
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import serial

W, H = 160, 120
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import nnref


def read_line(port, timeout=5.0):
    end = time.monotonic() + timeout
    buf = b''
    while time.monotonic() < end:
        c = port.read(1)
        if not c:
            continue
        if c == b'\n':
            return buf.decode(errors='replace')
        buf += c
    raise TimeoutError(f'等不到一行, 已收到 {buf!r}')


def grab(port):
    """-> (板子结果 dict 或 None, RGB 图 120x160x3)"""
    port.reset_input_buffer()
    port.write(b'g')
    while True:
        line = read_line(port, 10.0)
        if line.startswith('NNGRAB'):
            break
    parts = line.split()
    if parts[1] == 'ERR':
        print(f'  板子: 抓帧失败 ({line})')
        return None, None
    heat, x, y, fist = (int(v) for v in parts[1:5])
    raw = port.read(W * H * 3)
    if len(raw) != W * H * 3:
        raise TimeoutError(f'像素没收全: {len(raw)} / {W * H * 3}')
    img = np.frombuffer(raw, np.uint8).reshape(H, W, 3)
    return {'heat': heat, 'x': x, 'y': y, 'fist': fist}, img


def pc_result(model, img):
    """同 sw/nn/nn_post.h 的 nn_decode: 热力图最大的一格"""
    out = nnref.run(model, img)
    heat = out[:, 0].astype(np.int32)
    k = int(heat.argmax())
    return int(heat[k]), k


def main():
    ap = argparse.ArgumentParser(usage=__doc__)
    ap.add_argument('--port', default='/dev/ttyUSB0')
    ap.add_argument('-n', type=int, default=1)
    ap.add_argument('--every', type=float, default=0.0)
    ap.add_argument('--out', default='build/grab')
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    model = nnref.load(HERE.parent / 'tests/nn/model.npz')
    with serial.Serial(args.port, 115200, timeout=0.5) as port:
        for i in range(args.n):
            board, img = grab(port)
            if img is None:
                continue
            path = out / f'grab_{i:03d}.png'
            cv2.imwrite(str(path), img[:, :, ::-1])
            q, cell = pc_result(model, img)
            lo, mean, hi = img.reshape(-1, 3).min(0), img.reshape(-1, 3).mean(0), img.reshape(-1, 3).max(0)
            print(
                f'{path}: 板子 热力图 {board["heat"]} 手心 ({board["x"]}, {board["y"]}) 握拳 {board["fist"]}; '
                f'电脑 nnref 最大格 {cell} (logit {q}); '
                f'RGB 最小 {lo.tolist()} 平均 {[round(v) for v in mean]} 最大 {hi.tolist()}'
            )
            if args.every:
                time.sleep(args.every)


if __name__ == '__main__':
    main()
