#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "opencv-python", "mediapipe"]
# ///
"""消融: 同一段视频, 帧差找手的各种组合 (motion.locate 的开关 + 肤色) 和 MediaPipe 手心比, 打印一张表。

用法: model/ablate.py <hand_landmarker.task> <视频文件>
只统计两边都给出点的帧; 距离单位是 160x120 下的点。
"""

import sys
from itertools import product

import cv2
import numpy as np

from motion import H, MIN_POINTS, NEAR, THRESHOLD, W, box4, gray, hand_detector, hands_in, locate, skin, to_vga


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    detector = hand_detector(sys.argv[1])
    cap = cv2.VideoCapture(sys.argv[2])
    if not cap.isOpened():
        sys.exit(f'打不开 {sys.argv[2]}')
    step = max(1, int(1000 / cap.get(cv2.CAP_PROP_FPS)))

    # 先把每帧的运动掩码、肤色和 MediaPipe 手心都算好, 各种组合共用
    masks, skins, centers = [], [], []
    prev = None
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        vga = to_vga(cv2.flip(frame, 1))
        small = box4(vga)
        cur = gray(small)
        masks.append(cv2.absdiff(cur, cur if prev is None else prev) > THRESHOLD)
        skins.append(skin(small))
        centers.append([(h[9].x * W, h[9].y * H) for h in hands_in(detector, vga, len(masks) * step)])
        prev = cur
    print(f'{len(masks)} 帧, MediaPipe 看到手 {sum(1 for c in centers if c)} 帧\n')

    print(f'{"肤色":<4} {"分格":<4} {"跟踪门":<4} {"有点":>5} {"跟上":>6} {"平均":>6} {"中位":>6} {"90%":>6}')
    for use_skin, grid, gate in product([False, True], repeat=3):
        errors = []
        point = None
        for mask, sk, hands in zip(masks, skins, centers):
            point = locate(mask & sk if use_skin else mask, point, grid, gate, MIN_POINTS)
            if point and hands:
                errors.append(min(np.hypot(point[0] - x, point[1] - y) for x, y in hands))
        e = np.array(errors)
        mark = ['', '✓']
        stats = (
            f'{np.mean(e <= NEAR):>6.0%} {e.mean():>6.1f} {np.median(e):>6.1f} {np.percentile(e, 90):>6.1f}'
            if len(e)
            else f'{"—":>6} {"—":>6} {"—":>6} {"—":>6}'  # 一个点都没找到 (比如肤色把运动点全滤掉了)
        )
        print(f'{mark[use_skin]:<5} {mark[grid]:<5} {mark[gate]:<5} {len(e):>6} {stats}')
    print(f'\n跟上: 离手心不超过 {NEAR} 点的比例; 平均/中位/90%: 离手心的距离')


if __name__ == '__main__':
    main()
