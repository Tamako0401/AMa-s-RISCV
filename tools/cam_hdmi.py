#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "opencv-python"]
# ///
"""摄像头 -> HDMI 输入: 板子没有直接接摄像头的接口, 用电脑把 USB 摄像头的画面原样画到接 FPGA HDMI 输入的那块屏上。

用法: tools/cam_hdmi.py [--cam 0] [--screen 1280x720] [--out window|fb]    窗口里按 Esc 或 Ctrl+C 退出
  画面镜像 (像照镜子: 手往右, 画面里也往右), 裁成 4:3 缩到 640x480, 画在屏幕正中;
  FPGA 的 crop 从输入正中裁 640x480 (rtl/vision), 所以板上看到的就是这 640x480, 坐标不用换算。
  --out window: 开全屏窗口, 拖到接 FPGA 的那块屏上 (--screen 写那块屏的分辨率);
        fb: 直接写 /dev/fb0 (没有桌面的 Linux 小板子)。
  --cam: 摄像头编号, 或一个放 jpg 的目录 (按 15 帧/秒循环播放, 不接摄像头时测试用)。
  键盘、鼠标、手柄用 ama monitor --pad (tools/ama/pad.py), 和这个程序无关。
"""

import argparse
import time
from pathlib import Path

import cv2
import numpy as np

W, H = 640, 480
FB = '/sys/class/graphics/fb0/'


def to_vga(frame):
    """裁成 4:3, 缩到 640x480"""
    h, w = frame.shape[:2]
    if (w, h) == (W, H):
        return frame
    cw = min(w, h * 4 // 3)
    ch = cw * 3 // 4
    frame = frame[(h - ch) // 2 : (h + ch) // 2, (w - cw) // 2 : (w + cw) // 2]
    return cv2.resize(frame, (W, H), interpolation=cv2.INTER_AREA)


class Source:
    """摄像头, 或者一个 jpg 目录 (按 15 帧/秒循环播放)"""

    def __init__(self, cam):
        self.files = sorted(Path(cam).glob('*.jpg')) if not cam.isdigit() else None
        if self.files is not None:
            if not self.files:
                raise SystemExit(f'{cam} 里没有 jpg')
            self.i, self.next = 0, time.monotonic()
            return
        self.cap = cv2.VideoCapture(int(cam))
        self.cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, W)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, H)
        self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)  # 只留最新一帧, 不攒延迟
        if not self.cap.isOpened():
            raise SystemExit(f'打不开摄像头 {cam}')

    def read(self):
        """-> 镜像后的 640x480 BGR, 或 None"""
        if self.files is None:
            ok, frame = self.cap.read()
            return to_vga(cv2.flip(frame, 1)) if ok else None
        self.next += 1 / 15
        time.sleep(max(0.0, self.next - time.monotonic()))
        frame = cv2.imread(str(self.files[self.i % len(self.files)]))  # 录的数据已经镜像
        self.i += 1
        return to_vga(frame)


def open_fb():
    """把 fb0 映射成 numpy 数组 (高, 宽, 4), 每个点 B G R X"""
    width, height = (int(v) for v in Path(FB + 'virtual_size').read_text().split(','))
    stride = int(Path(FB + 'stride').read_text())
    fb = np.memmap('/dev/fb0', dtype=np.uint8, mode='r+', shape=(height, stride))
    return fb[:, : width * 4].reshape(height, width, 4)


def main():
    parser = argparse.ArgumentParser(usage=__doc__)
    parser.add_argument('--cam', default='0')
    parser.add_argument('--screen', default='1280x720')
    parser.add_argument('--out', choices=['window', 'fb'], default='window')
    args = parser.parse_args()

    source = Source(args.cam)
    if args.out == 'fb':
        whole = open_fb()
    else:
        sw, sh = (int(v) for v in args.screen.split('x'))
        whole = np.zeros((sh, sw, 4), np.uint8)
        cv2.namedWindow('cam_hdmi', cv2.WINDOW_NORMAL)
        cv2.setWindowProperty('cam_hdmi', cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
    whole[:] = 0
    y0, x0 = (whole.shape[0] - H) // 2, (whole.shape[1] - W) // 2
    screen = whole[y0 : y0 + H, x0 : x0 + W, :3]
    print(f'屏幕 {whole.shape[1]}x{whole.shape[0]}, 画面放在 ({x0}, {y0})')
    shown, t = 0, time.monotonic()
    try:
        while True:
            frame = source.read()
            if frame is None:
                print('摄像头没读到画面')
                time.sleep(0.5)
                continue
            screen[:] = frame
            shown += 1
            if args.out == 'window':
                cv2.imshow('cam_hdmi', whole)
                if cv2.waitKey(1) == 27:
                    break
            if time.monotonic() - t >= 5:
                print(f'{shown / (time.monotonic() - t):.1f} 帧/秒', flush=True)
                shown, t = 0, time.monotonic()
    except KeyboardInterrupt:
        pass
    finally:
        if args.out == 'fb':
            whole[:] = 0


if __name__ == '__main__':
    main()
