#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "opencv-python", "mediapipe"]
# ///
"""颜色标记跟踪: 手里拿一个颜色鲜艳的东西, 找画面里这个颜色的点 -> 重心 -> 轨迹 (标记可能比分格的窗口大, 不分格)。

用法: model/color.py <视频文件 | 摄像头编号 | 网络流 URL>
在左边画面上点一下标记物, 取那里的颜色 (Cb, Cr); 之后颜色在 Cb, Cr 各差不超过 tolerance 的点算标记。
窗口: 左边是画面 (红点/绿线是找到的位置和轨迹), 右边是颜色掩码。空格暂停, q 退出, 退出时打印统计。
"""

import sys
import time

import cv2
import numpy as np

from motion import SHOW, TRAIL, H, W, box4, chroma, locate, open_source, to_vga


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    cap, fps = open_source(sys.argv[1])
    is_file = not sys.argv[1].isdigit() and '://' not in sys.argv[1]

    target = None  # 点选的 (Cb, Cr)
    small = None

    def pick(event, x, y, flags, param):
        nonlocal target
        if event == cv2.EVENT_LBUTTONDOWN and small is not None and x < W * SHOW:
            cb, cr = chroma(small)
            x, y = x // SHOW, y // SHOW
            area = (slice(max(0, y - 1), y + 2), slice(max(0, x - 1), x + 2))  # 3x3 平均
            target = int(cb[area].mean()), int(cr[area].mean())
            print(f'颜色 Cb={target[0]} Cr={target[1]}')

    cv2.namedWindow('color')
    cv2.setMouseCallback('color', pick)
    cv2.createTrackbar('tolerance', 'color', 12, 64, lambda _: None)
    cv2.createTrackbar('min points', 'color', 10, 500, lambda _: None)

    trail = []
    paused = False
    frames = found = 0
    while True:
        if not paused:
            start = time.time()
            ok, frame = cap.read()
            if not ok:
                if not is_file:
                    break
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)  # 文件放完从头再来
                trail = []
                continue
            small = box4(to_vga(cv2.flip(frame, 1)))
            mask = np.zeros((H, W), bool)
            if target:
                cb, cr = chroma(small)
                tol = cv2.getTrackbarPos('tolerance', 'color')
                mask = (abs(cb - target[0]) <= tol) & (abs(cr - target[1]) <= tol)
            point = locate(mask, None, False, False, cv2.getTrackbarPos('min points', 'color'))
            trail = (trail + [point])[-TRAIL:]
            if target:
                frames += 1
                found += point is not None

            panels = [small, cv2.cvtColor(mask.astype(np.uint8) * 255, cv2.COLOR_GRAY2BGR)]
            panels = [cv2.resize(p, (W * SHOW, H * SHOW), interpolation=cv2.INTER_NEAREST) for p in panels]
            for a, b in zip(trail, trail[1:]):
                if a and b:
                    cv2.line(panels[0], (a[0] * SHOW, a[1] * SHOW), (b[0] * SHOW, b[1] * SHOW), (0, 255, 0), 2)
            if point:
                cv2.circle(panels[0], (point[0] * SHOW, point[1] * SHOW), 6, (0, 0, 255), -1)
            text = f'Cb={target[0]} Cr={target[1]}  found {found}/{frames}' if target else 'click the marker'
            cv2.putText(panels[1], text, (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 200, 255), 2)
            cv2.imshow('color', np.hstack(panels))

        # 文件按原速播放; 摄像头有一帧算一帧
        wait = max(1, int(1000 / fps - (time.time() - start) * 1000)) if is_file and fps > 0 and not paused else 1
        key = cv2.waitKey(wait) & 0xFF
        if key == ord('q'):
            break
        if key == ord(' '):
            paused = not paused

    if target:
        print(f'颜色 Cb={target[0]} Cr={target[1]}; 选色之后 {frames} 帧, 找到标记 {found} 帧')


if __name__ == '__main__':
    main()
