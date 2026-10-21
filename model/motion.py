#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "opencv-python", "mediapipe"]
# ///
"""运动轨迹试验: 帧差 -> 阈值 -> 运动掩码 -> 重心 -> 轨迹, 在 160x120 下做 (和 box4 之后硬件看到的一样)。
同时跑 MediaPipe 手部 21 点当对照, 看帧差的重心离真正的手有多远。

用法: model/motion.py <hand_landmarker.task> <视频文件 | 摄像头编号 | 网络流 URL>
  模型下载: https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
窗口从左到右: 缩小后的输入 (叠 MediaPipe 的手)、帧差、运动掩码。
  红点/绿线: 帧差的重心和轨迹; 蓝点: MediaPipe 的手心 (21 点里的 9 号, 中指根)。
画面左右镜像, 像照镜子。空格暂停, q 退出; 滑条调阈值和最少运动点数。退出时打印统计。
按键开关 (见 locate): g 分格取最大, k 跟踪门, s 只算肤色点。同一段视频比较各种组合用 model/ablate.py。
"""

import sys
import time

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions, vision

W, H = 160, 120
SHOW = 3  # 显示时每个点放大几倍
TRAIL = 15  # 轨迹留几帧
NEAR = 10  # 重心离手心不超过几个点 (160x120 下) 算跟上了
THRESHOLD = 20  # 帧差超过多少算在动 (滑条初值)
MIN_POINTS = 30  # 运动点少于这么多算没在动 (滑条初值)
CELL = 8  # 分格取最大: 每格 8x8, 160x120 分成 20x15 格
GATE = 24  # 跟踪门: 只看上一帧位置上下左右 24 点以内


def to_vga(frame):
    """裁成 4:3, 缩到 640x480, 相当于电脑经 HDMI 送进来的画面。"""
    h, w = frame.shape[:2]
    cw = min(w, h * 4 // 3)
    ch = cw * 3 // 4
    frame = frame[(h - ch) // 2 : (h + ch) // 2, (w - cw) // 2 : (w + cw) // 2]
    return cv2.resize(frame, (640, 480), interpolation=cv2.INTER_AREA)


def box4(vga):
    """4x4 均值缩到 160x120, 和 rtl/vision/box4.v 一样取整。"""
    return (vga.astype(np.uint16).reshape(H, 4, W, 4, 3).sum((1, 3)) >> 4).astype(np.uint8)


def gray(img):
    """亮度取 (R + 2G + B) / 4, 硬件上只要加法和移位。OpenCV 读进来是 BGR。"""
    b, g, r = (img[..., i].astype(np.uint16) for i in range(3))
    return ((r + 2 * g + b) >> 2).astype(np.uint8)


def chroma(img):
    """BGR -> YCbCr 里的 Cb, Cr (颜色, 和亮度无关); 系数是 8 位定点, 硬件上是几个乘加。"""
    b, g, r = (img[..., i].astype(np.int32) for i in range(3))
    return 128 + ((-43 * r - 85 * g + 128 * b) >> 8), 128 + ((128 * r - 107 * g - 21 * b) >> 8)


def skin(img):
    """肤色: Cb 在 77..127 且 Cr 在 133..173 (Chai & Ngan 1999 的常用范围)。"""
    cb, cr = chroma(img)
    return (cb >= 77) & (cb <= 127) & (cr >= 133) & (cr <= 173)


def locate(mask, prev, grid, gate, min_points):
    """运动掩码 -> 一个点 (或 None)。基线是全部运动点的重心, 两个开关去掉干扰:
    gate: 只留上一帧位置附近的点; 附近没有运动就放开, 回到全图重新找。
    grid: 数每格的运动点, 只留最多那格和它周围一圈 (3x3 格) 的点。"""
    if mask.sum() < min_points:
        return None
    if gate and prev:
        x, y = prev
        near = np.zeros_like(mask)
        near[max(0, y - GATE) : y + GATE, max(0, x - GATE) : x + GATE] = True
        if (mask & near).sum() >= min_points:
            mask = mask & near
    if grid:
        counts = mask.reshape(H // CELL, CELL, W // CELL, CELL).sum((1, 3))
        cy, cx = np.unravel_index(counts.argmax(), counts.shape)
        keep = np.zeros_like(mask)
        keep[max(0, cy - 1) * CELL : (cy + 2) * CELL, max(0, cx - 1) * CELL : (cx + 2) * CELL] = True
        mask = mask & keep
    # 重心 = 运动点坐标的平均; 硬件上是三个累加器 (个数, x 之和, y 之和), 一帧结束做一次除法
    ys, xs = np.nonzero(mask)
    return int(xs.mean()), int(ys.mean())


def hand_detector(model):
    return vision.HandLandmarker.create_from_options(
        vision.HandLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=model), running_mode=vision.RunningMode.VIDEO, num_hands=2
        )
    )


def hands_in(detector, vga, stamp):
    """MediaPipe 在 640x480 上找手; stamp 是毫秒时间戳, 必须一直增大。"""
    image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(vga, cv2.COLOR_BGR2RGB))
    return detector.detect_for_video(image, stamp).hand_landmarks


def open_source(arg):
    cap = cv2.VideoCapture(int(arg) if arg.isdigit() else arg)
    if not cap.isOpened():
        sys.exit(f'打不开 {arg}')
    fps = cap.get(cv2.CAP_PROP_FPS)
    print(f'{arg}: {int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))}x{int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))} {fps:.0f} fps')
    return cap, fps


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    hands = hand_detector(sys.argv[1])
    cap, fps = open_source(sys.argv[2])
    is_file = not sys.argv[2].isdigit() and '://' not in sys.argv[2]

    cv2.namedWindow('motion')
    cv2.createTrackbar('threshold', 'motion', THRESHOLD, 255, lambda _: None)
    cv2.createTrackbar('min points', 'motion', MIN_POINTS, 2000, lambda _: None)

    prev = None
    trail = []
    use = {'g': False, 'k': False, 's': False}
    paused = False
    stamp = 0  # MediaPipe 要求时间戳一直增大, 文件重播也不归零
    frames = with_hand = near = 0
    errors = []
    while True:
        if not paused:
            start = time.time()
            ok, frame = cap.read()
            if not ok:
                if not is_file:
                    break
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)  # 文件放完从头再来
                prev, trail = None, []
                continue
            vga = to_vga(cv2.flip(frame, 1))
            small = box4(vga)
            cur = gray(small)
            if prev is None:
                prev = cur
            diff = cv2.absdiff(cur, prev)
            prev = cur

            mask = diff > cv2.getTrackbarPos('threshold', 'motion')
            if use['s']:
                mask &= skin(small)
            count = int(mask.sum())
            point = locate(
                mask, trail[-1] if trail else None, use['g'], use['k'], cv2.getTrackbarPos('min points', 'motion')
            )
            trail = (trail + [point])[-TRAIL:]

            # 对照: MediaPipe 的手, 坐标换算到 160x120
            stamp += max(1, int(1000 / fps)) if fps > 0 else 33
            found = hands_in(hands, vga, stamp)
            centers = [(hand[9].x * W, hand[9].y * H) for hand in found]

            frames += 1
            if centers:
                with_hand += 1
            if centers and point:
                err = min(np.hypot(point[0] - x, point[1] - y) for x, y in centers)
                errors.append(err)
                near += err <= NEAR

            panels = [
                small,
                cv2.cvtColor(diff, cv2.COLOR_GRAY2BGR),
                cv2.cvtColor(mask.astype(np.uint8) * 255, cv2.COLOR_GRAY2BGR),
            ]
            panels = [cv2.resize(p, (W * SHOW, H * SHOW), interpolation=cv2.INTER_NEAREST) for p in panels]
            for hand in found:
                pts = [(int(p.x * W * SHOW), int(p.y * H * SHOW)) for p in hand]
                for c in vision.HandLandmarksConnections.HAND_CONNECTIONS:
                    cv2.line(panels[0], pts[c.start], pts[c.end], (0, 255, 0), 1)
                for p in pts:
                    cv2.circle(panels[0], p, 3, (0, 0, 255), -1)
            for x, y in centers:
                cv2.circle(panels[2], (int(x * SHOW), int(y * SHOW)), 6, (255, 128, 0), -1)
            for a, b in zip(trail, trail[1:]):
                if a and b:
                    cv2.line(panels[2], (a[0] * SHOW, a[1] * SHOW), (b[0] * SHOW, b[1] * SHOW), (0, 255, 0), 2)
            if point:
                cv2.circle(panels[2], (point[0] * SHOW, point[1] * SHOW), 6, (0, 0, 255), -1)
            on = ' '.join(k for k, v in use.items() if v)
            cv2.putText(panels[2], f'points {count}  [{on}]', (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 200, 255), 2)
            if errors:
                text = f'near {near}/{len(errors)}  mean {np.mean(errors):.1f}'
                cv2.putText(panels[2], text, (8, 50), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 200, 255), 2)
            cv2.imshow('motion', np.hstack(panels))

        # 文件按原速播放; 摄像头有一帧算一帧
        wait = max(1, int(1000 / fps - (time.time() - start) * 1000)) if is_file and fps > 0 and not paused else 1
        key = cv2.waitKey(wait) & 0xFF
        if key == ord('q'):
            break
        if key == ord(' '):
            paused = not paused
        if chr(key) in use:
            use[chr(key)] = not use[chr(key)]
            near, errors = 0, []  # 换了方法, 统计重新算

    print(f'帧 {frames}, MediaPipe 看到手 {with_hand}, 两边都有点 {len(errors)}')
    if errors:
        print(
            f'重心离手心 <= {NEAR} 点: {near}/{len(errors)} ({near / len(errors):.0%}), 平均 {np.mean(errors):.1f} 点'
        )


if __name__ == '__main__':
    main()
