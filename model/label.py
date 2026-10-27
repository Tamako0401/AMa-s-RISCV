#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "opencv-python", "mediapipe"]
# ///
"""MediaPipe 当老师, 给 model/record.py 录的数据自动标注: 手在哪 (手掌中心)、握拳还是张开。
结果存成每个 session 目录下的 labels.npz; 按段打印统计, 和录制时要求的动作对不上的帧就是要查的地方。

用法: model/label.py <gesture_recognizer.task> <session 目录...>
  模型下载: https://storage.googleapis.com/mediapipe-models/gesture_recognizer/gesture_recognizer/float16/latest/gesture_recognizer.task
手势两路来源: MediaPipe Gesture Recognizer 自带的 Closed_Fist / Open_Palm, 和按手指弯曲程度的规则 (rule)。
一路说不清时听另一路; 两路矛盾 (一个说握拳一个说张开) 或都说不清标 IGNORE (训练时这帧不算手势, 位置照算)。
labels.npz 的字段见 docs/hand-model.md。
"""

import json
import sys
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions, vision

from record import SEGMENTS

MAX_HANDS = 2
PALM = [0, 5, 9, 13, 17]  # 手腕 + 四个指根; 握拳、张开时这几个点基本不动, 手掌中心取它们的平均
FINGERS = [(5, 8), (9, 12), (13, 16), (17, 20)]  # (指根, 指尖), 食指到小指; 拇指形态多变, 不看
FIST_BELOW = 1.2  # 规则: 四指的 (指尖到手腕) / (指根到手腕) 都小于它算握拳
OPEN_ABOVE = 1.6  # 都大于它算张开; 中间的说不清
FIST, OPEN, IGNORE = 0, 1, -1
TEACHER = {'Closed_Fist': FIST, 'Open_Palm': OPEN}  # 其余 (None、Victory 等) 都算 IGNORE


def recognizer(model, still=False):
    """still: 帧之间互不相关 (导入的照片, 见 import_hagrid.py), 用 IMAGE 模式逐张识别; 否则 VIDEO 模式利用前后帧。"""
    mode = vision.RunningMode.IMAGE if still else vision.RunningMode.VIDEO
    return vision.GestureRecognizer.create_from_options(
        vision.GestureRecognizerOptions(base_options=BaseOptions(model_asset_path=model), running_mode=mode, num_hands=MAX_HANDS)
    )


def finger_ratios(world):
    """四指各自 (指尖到手腕) / (指根到手腕)。用 world 坐标 (以手为原点的三维米制坐标), 手转个角度比值也不怎么变。"""
    p = np.array([[q.x, q.y, q.z] for q in world])
    return np.array([np.linalg.norm(p[tip] - p[0]) / np.linalg.norm(p[base] - p[0]) for base, tip in FINGERS])


def rule(ratios):
    if (ratios < FIST_BELOW).all():
        return FIST
    if (ratios > OPEN_ABOVE).all():
        return OPEN
    return IGNORE


def merge(teacher, by_rule):
    """两路说不清的情况互补: 实测老师常对移动中的拳头说 None, 规则常对移动中微弯的张开手说不清;
    两路直接矛盾的帧很少 (2026-10-23 第一次录制 0 帧), 出现就不用。"""
    if teacher == IGNORE:
        return by_rule
    if by_rule == IGNORE or by_rule == teacher:
        return teacher
    return IGNORE


def label(detector, session, still=False):
    meta = json.loads((session / 'meta.json').read_text())
    frames = meta['frames']
    n = len(frames)
    out = {
        'files': np.array([f['file'] for f in frames]),
        'segment': np.array([f['segment'] for f in frames]),
        'hands': np.zeros(n, np.int8),
        'points': np.full((n, MAX_HANDS, 21, 2), np.nan, np.float32),
        'center': np.full((n, MAX_HANDS, 2), np.nan, np.float32),
        'teacher': np.full((n, MAX_HANDS), IGNORE, np.int8),
        'teacher_score': np.zeros((n, MAX_HANDS), np.float32),
        'ratios': np.full((n, MAX_HANDS, 4), np.nan, np.float32),
        'rule': np.full((n, MAX_HANDS), IGNORE, np.int8),
        'gesture': np.full((n, MAX_HANDS), IGNORE, np.int8),
    }
    out['expect'] = meta.get('expect', {})  # 每段应该看到什么 (record.py 写的; 早期录制没有这项)
    stamp = -1
    for i, f in enumerate(frames):
        vga = cv2.imread(str(session / f['file']))
        stamp = max(stamp + 1, f['t_ms'])  # VIDEO 模式要求时间戳严格增大
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(vga, cv2.COLOR_BGR2RGB))
        result = detector.recognize(image) if still else detector.recognize_for_video(image, stamp)
        hands = list(zip(result.hand_landmarks, result.hand_world_landmarks, result.gestures))
        hands.sort(key=lambda h: np.mean([q.x for q in h[0]]))  # 两只手按左右排, 顺序固定
        out['hands'][i] = len(hands)
        for k, (points, world, gestures) in enumerate(hands):
            # 坐标存 0..1 的比例 (MediaPipe 原样), 换成任何分辨率都是乘宽高
            pts = np.array([[q.x, q.y] for q in points], np.float32)
            out['points'][i, k] = pts
            out['center'][i, k] = pts[PALM].mean(0)
            top = gestures[0]
            out['teacher'][i, k] = TEACHER.get(top.category_name, IGNORE)
            out['teacher_score'][i, k] = top.score
            ratios = finger_ratios(world)
            out['ratios'][i, k] = ratios
            out['rule'][i, k] = rule(ratios)
            out['gesture'][i, k] = merge(out['teacher'][i, k], out['rule'][i, k])
        if (i + 1) % 200 == 0:
            print(f'  {i + 1}/{n}', end='\r')
    print(' ' * 20, end='\r')  # 擦掉进度
    np.savez_compressed(session / 'labels.npz', **{k: v for k, v in out.items() if k != 'expect'})
    return out


def report(out):
    """按段打表 (手势只看第一只手)。矛盾: 老师和规则一个说握拳一个说张开; 弃权: 一路说不清、由另一路定;
    对不上: 帧里的标注和这段要求的动作矛盾 (老师错了或人没照做)。"""
    expect = out['expect'] or {name: e for name, _, e, _ in SEGMENTS}
    heads = ['有手', '两手', '握拳', '张开', '忽略', '矛盾', '弃权']
    print(f'  {"段":<11}{"帧":>3}' + ''.join(f'{h:>4}' for h in heads) + f'{"对不上":>4}')  # 中文占两格, 少补一半空格
    for name in dict.fromkeys(out['segment']):  # 按录制顺序, 每段一行
        sel = out['segment'] == name
        n = int(sel.sum())
        if not n:
            continue
        hands = out['hands'][sel]
        first = out['gesture'][sel, 0]  # 只看第一只手的手势 (单手段只有一只)
        found = hands > 0
        teacher, by_rule = out['teacher'][sel, 0], out['rule'][sel, 0]
        clash = found & (teacher != IGNORE) & (by_rule != IGNORE) & (teacher != by_rule)
        abstain = found & ((teacher == IGNORE) != (by_rule == IGNORE))  # 一路说不清, 由另一路定
        e = expect.get(name, 'maybe')
        if e == 'maybe':
            wrong = np.zeros(n, bool)
        elif e == 'none':
            wrong = hands > 0
        elif e == 'two':
            wrong = hands != 2
        elif e == 'any':
            wrong = hands != 1
        else:
            wrong = (hands != 1) | (first == (OPEN if e == 'fist' else FIST))  # IGNORE 不算错, 只是不用
        cols = [found, hands == 2, found & (first == FIST), found & (first == OPEN), found & (first == IGNORE), clash, abstain]
        print(f'  {name:<12}{n:>4}' + ''.join(f'{m.mean():>6.0%}' for m in cols) + f'{int(wrong.sum()):>7}')

    # 规则阈值对不对: 看两段静止时四指比值的范围, 握拳的最大值应低于 FIST_BELOW, 张开的最小值应高于 OPEN_ABOVE
    for name in ('fist_still', 'open_still'):
        r = out['ratios'][out['segment'] == name, 0]
        r = r[~np.isnan(r).any(1)]
        if len(r):
            lo, hi = np.percentile(r.min(1), 5), np.percentile(r.max(1), 95)
            print(f'  {name}: 四指比值 最小值的 5% 分位 {lo:.2f}, 最大值的 95% 分位 {hi:.2f}')
    print(f'  (规则阈值: 握拳 < {FIST_BELOW}, 张开 > {OPEN_ABOVE})')


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    for arg in sys.argv[2:]:
        session = Path(arg)
        print(f'{session.name}:')
        still = json.loads((session / 'meta.json').read_text()).get('still', False)
        # 每个 session 新建一个识别器: VIDEO 模式会利用前后帧, 不能跨 session 接着用
        with recognizer(sys.argv[1], still) as detector:
            report(label(detector, session, still))


if __name__ == '__main__':
    main()
