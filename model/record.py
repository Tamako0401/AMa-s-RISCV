#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "opencv-python", "mediapipe"]
# ///
"""录手势数据: 屏幕按固定顺序提示做什么动作, 每段录几秒, 存成 640x480 的 JPEG (和 motion.to_vga 一样, 相当于
电脑经 HDMI 送进来的画面)。之后用 model/label.py 让 MediaPipe 自动标注。流程和数据格式见 docs/hand-model.md。

用法: model/record.py <人> <场景> [摄像头编号, 默认 0]
  人: 录的是谁, 字母数字即可 (如 ps)。训练集和测试集按人分开, 同一个人每次用同一个名字。
  场景: 光线和背景, 如 front (顺光)、back (逆光)、messy (杂乱背景)。
存到 model/data/<日期>_<人>_<场景>_<时分秒>/: 帧图片 + meta.json (每帧属于哪一段、时间戳)。
每段开始前倒数 2 秒 (不存)。空格暂停, r 重录当前段, n 跳过当前段, q 结束 (已录完的段保留)。
"""

import json
import shutil
import sys
import time
from pathlib import Path

import cv2

from motion import open_source, to_vga

DATA = Path(__file__).parent / 'data'
SAVE_EVERY = 2  # 每 2 帧存 1 帧: 相邻帧几乎一样, 全存只多占地方
QUALITY = 95  # JPEG 质量
COUNTDOWN = 2.0  # 每段开始前倒数几秒

# (段名, 秒数, 应该看到什么, 屏幕提示)。按游戏的玩法排: 平时握拳移动, 张开一下放 bomb; 摄像头在显示器上方
# 对着人, 手在胸前 (2026-10-23 试过放桌面平拍: 手太大、多是侧面, 老师认不出手势, 也更难玩)。
# "应该看到什么" 给 label.py 核对老师: open / fist / any (有一只手, 手势不限) / none (没有手) / two (两只手)
# / maybe (手可能在画面外, 不核对); 和老师的标注对不上的帧, 要么老师错了, 要么人没照做, 都要看一眼。
SEGMENTS = [
    ('fist_still', 5, 'fist', 'FIST, hold still'),
    ('open_still', 5, 'open', 'OPEN hand, hold still'),
    ('move_fist', 15, 'fist', 'FIST, move around (like playing)'),
    ('swipe_fist', 10, 'fist', 'FIST, move fast'),
    ('bomb', 15, 'any', 'FIST moving, flash OPEN now and then'),
    ('turn', 10, 'any', 'turn hand: palm / side / back, FIST and OPEN'),
    ('other_hand', 10, 'any', 'OTHER hand: FIST moving, flash OPEN'),
    ('far_near', 10, 'any', 'move hand closer / farther'),
    ('edge', 10, 'maybe', 'move hand in and out of view'),
    ('near_face', 10, 'any', 'FIST moving near / in front of face'),
    ('no_hand', 5, 'none', 'NO hand, stay in view'),
    ('face', 5, 'none', 'NO hand, lean in to camera'),
    ('two_hands', 5, 'two', 'TWO hands, move'),
]


def new_session(person, scene, kind=''):
    """新建一次录制的目录: model/data/<日期>_<人>_<场景>[_<kind>]_<时分秒>/。"""
    name = '_'.join(x for x in (time.strftime('%Y%m%d'), person, scene, kind, time.strftime('%H%M%S')) if x)
    out = DATA / name
    out.mkdir(parents=True)
    return out


def overlay(vga, index, prompt, line, color):
    """画面上叠提示: 第几段、做什么、倒数或剩余秒数。"""
    shown = vga.copy()
    cv2.rectangle(shown, (0, 0), (640, 70), (0, 0, 0), -1)
    cv2.putText(shown, f'{index + 1}/{len(SEGMENTS)}  {prompt}', (10, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    cv2.putText(shown, line, (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, 2)
    return shown


def segment(cap, out, index, start, frames):
    """录一段, 帧追加进 frames。返回 'next' (录完)、'skip'、'redo' 或 'quit'。"""
    name, seconds, _, prompt = SEGMENTS[index]
    begin = time.monotonic()
    paused_at = None
    count = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            return 'quit'
        vga = to_vga(cv2.flip(frame, 1))  # 左右镜像, 像照镜子; 训练时会随机翻转, 方向无所谓
        now = time.monotonic()
        t = now - begin - COUNTDOWN
        if paused_at is not None:
            shown = overlay(vga, index, prompt, 'PAUSED (space)', (0, 200, 255))
        elif t < 0:
            shown = overlay(vga, index, prompt, f'get ready  {-t:.0f}', (0, 200, 255))
        elif t < seconds:
            if count % SAVE_EVERY == 0:
                file = f'{index:02d}_{name}_{count:04d}.jpg'
                cv2.imwrite(str(out / file), vga, [cv2.IMWRITE_JPEG_QUALITY, QUALITY])
                frames.append({'file': file, 'segment': name, 't_ms': int((now - start) * 1000)})
            count += 1
            shown = overlay(vga, index, prompt, f'REC  {seconds - t:.0f}', (0, 0, 255))
            cv2.rectangle(shown, (0, 470), (int(640 * t / seconds), 480), (0, 0, 255), -1)
        else:
            return 'next'
        cv2.imshow('record', shown)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            return 'quit'
        if key == ord('r'):
            return 'redo'
        if key == ord('n'):
            return 'skip'
        if key == ord(' '):
            if paused_at is None:
                paused_at = now
            else:
                begin += now - paused_at  # 暂停的时间不算进这一段
                paused_at = None


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    person, scene = sys.argv[1:3]
    cap, _ = open_source(sys.argv[3] if len(sys.argv) == 4 else '0')
    out = new_session(person, scene)
    expect = {name: e for name, _, e, _ in SEGMENTS}
    meta = {'person': person, 'scene': scene, 'save_every': SAVE_EVERY, 'expect': expect, 'frames': []}
    start = time.monotonic()  # 时间戳从这里算, 一直增大 (MediaPipe 的 VIDEO 模式要求)
    index = 0
    while index < len(SEGMENTS):
        result = segment(cap, out, index, start, meta['frames'])
        name = SEGMENTS[index][0]
        if result != 'next':
            # 没录完的段整段丢掉, 不留半段
            for f in meta['frames']:
                if f['segment'] == name:
                    (out / f['file']).unlink()
            meta['frames'] = [f for f in meta['frames'] if f['segment'] != name]
        (out / 'meta.json').write_text(json.dumps(meta, indent=1, ensure_ascii=False))
        if result == 'quit':
            break
        if result != 'redo':
            index += 1
    cap.release()
    cv2.destroyAllWindows()

    if not meta['frames']:
        shutil.rmtree(out)
        sys.exit('一帧都没录, 不保存')
    print(f'存到 {out}: {len(meta["frames"])} 帧')
    for name, *_ in SEGMENTS:
        n = sum(f['segment'] == name for f in meta['frames'])
        print(f'  {name:<12} {n:>4}' if n else f'  {name:<12}    - (没录)')
    print(f'下一步: model/label.py <gesture_recognizer.task> {out}')


if __name__ == '__main__':
    main()
