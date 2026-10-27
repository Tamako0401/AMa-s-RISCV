#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "opencv-python"]
# ///
"""把 HaGRID 的照片导入成 record.py 那样的 session, 补自己录的数据里缺的: 人多、背景和光线多。

HaGRID (HAnd Gesture Recognition Image Dataset, https://github.com/hukenovs/hagrid) 是上万人对着手机摄像头做手势的照片,
许可 CC BY-SA 4.0 (用了要注明出处, 见 docs/hand-model.md "外部数据")。用的是缩到 384p 的抽样版
(https://huggingface.co/datasets/cj-mills/hagrid-sample-120k-384p, 一个 3.5 GB 的 zip, 同样 CC BY-SA 4.0)。

用法: model/import_hagrid.py <hagrid-sample-120k-384p.zip> [--per-class 2000] [--groups 10] [--classes fist palm stop]
之后照常: model/label.py models/gesture_recognizer.task model/data/*_hg*_hagrid_*   (照片按 IMAGE 模式逐张标注)

怎么转:
  - 每类按固定种子抽 per-class 张, 直接从 zip 里读, 不用解压。
  - 手机竖拍、人离得远, 手在原图里很小。裁一个 4:3 的窗口让手 (该类手势的那个框) 占窗口宽度的 10%~25%,
    和我们 "摄像头在显示器上方、手在胸前" 时差不多; 窗口至少 160 点宽 (网络只看 160x120), 不放大到比原图还糊。
    手不能完整放进窗口的照片不要。再缩放到 640x480, 和录的画面一样。
  - 一个人的照片放进同一组: user_id 哈希成 groups 组, 组名 hg00..hg09 当 "人", 一组一个 session。
    这样 train.py --val-person hg00 留出的是一批完全没见过的人。
  - 段名就是类别名; fist 应该握拳, palm、stop 应该张开 (label.py 据此报 "对不上")。
"""

import argparse
import hashlib
import json
import random
import time
import zipfile
from pathlib import Path

import cv2
import numpy as np

DATA = Path(__file__).parent / 'data'
ROOT = 'hagrid-sample-120k-384p'
EXPECT = {'fist': 'fist', 'palm': 'open', 'stop': 'open'}
HAND_FRAC = (0.10, 0.25)  # 手占窗口宽度的比例
MIN_CROP_W = 160


def crop_box(img_w, img_h, box, rng):
    """box: 手的框 (x, y, w, h), 像素。返回 4:3 窗口 (x0, y0, w, h), 手放不进去返回 None。"""
    bx, by, bw, bh = box
    max_w = min(img_w, img_h * 4 // 3)
    cw = int(np.clip(bw / rng.uniform(*HAND_FRAC), MIN_CROP_W, max_w))
    ch = cw * 3 // 4
    if bw > cw or bh > ch:
        return None
    # 窗口随机放, 只要手完整在里面 (手不总在正中间)
    x0 = rng.uniform(max(0, bx + bw - cw), min(bx, img_w - cw))
    y0 = rng.uniform(max(0, by + bh - ch), min(by, img_h - ch))
    if x0 < 0 or y0 < 0 or x0 + cw > img_w or y0 + ch > img_h:
        return None
    return int(x0), int(y0), cw, ch


def group_of(user_id, groups):
    return int(hashlib.sha1(user_id.encode()).hexdigest(), 16) % groups


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('zip')
    ap.add_argument('--per-class', type=int, default=2000)
    ap.add_argument('--groups', type=int, default=10)
    ap.add_argument('--classes', nargs='+', default=list(EXPECT))
    ap.add_argument('--seed', type=int, default=1)
    args = ap.parse_args()
    rng = np.random.default_rng(args.seed)

    stamp = time.strftime('%Y%m%d')
    sessions = {}  # 组号 -> (目录, frames 列表)

    def session(g):
        if g not in sessions:
            out = DATA / f'{stamp}_hg{g:02d}_hagrid_000000'
            if out.exists():
                raise SystemExit(f'{out} 已经存在: 删掉再导入, 或换 --seed 另导一批')
            out.mkdir(parents=True)
            sessions[g] = (out, [])
        return sessions[g]

    with zipfile.ZipFile(args.zip) as z:
        names = set(z.namelist())
        for cls in args.classes:
            ann = json.loads(z.read(f'{ROOT}/ann_train_val/{cls}.json'))
            # 抽样版只带了一部分照片, 只从 zip 里真有的里面抽
            ids = sorted(k for k in ann if f'{ROOT}/hagrid_120k/train_val_{cls}/{k}.jpg' in names)
            random.Random(args.seed).shuffle(ids)
            used = skipped = 0
            for k in ids:
                if used == args.per_class:
                    break
                a = ann[k]
                if cls not in a['labels']:
                    skipped += 1
                    continue
                buf = np.frombuffer(z.read(f'{ROOT}/hagrid_120k/train_val_{cls}/{k}.jpg'), np.uint8)
                img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
                h, w = img.shape[:2]
                x, y, bw, bh = a['bboxes'][a['labels'].index(cls)]
                win = crop_box(w, h, (x * w, y * h, bw * w, bh * h), rng)
                if win is None:
                    skipped += 1
                    continue
                x0, y0, cw, ch = win
                vga = cv2.resize(img[y0 : y0 + ch, x0 : x0 + cw], (640, 480), interpolation=cv2.INTER_AREA)
                out, frames = session(group_of(a['user_id'], args.groups))
                name = f'{cls}_{k}.jpg'
                cv2.imwrite(str(out / name), vga, [cv2.IMWRITE_JPEG_QUALITY, 95])
                frames.append({'file': name, 'segment': cls, 't_ms': len(frames)})
                used += 1
            print(f'{cls}: 用 {used} 张, 跳过 {skipped} 张 (手放不进窗口或标签不对)')

    for g, (out, frames) in sorted(sessions.items()):
        meta = {
            'person': f'hg{g:02d}',
            'scene': 'hagrid',
            'still': True,
            'expect': {c: EXPECT[c] for c in args.classes},
            'source': 'HaGRID (https://github.com/hukenovs/hagrid), CC BY-SA 4.0; '
            'sample: https://huggingface.co/datasets/cj-mills/hagrid-sample-120k-384p',
            'frames': frames,
        }
        (out / 'meta.json').write_text(json.dumps(meta, indent=1, ensure_ascii=False))
        print(f'{out.name}: {len(frames)} 张')
    print(f'下一步: model/label.py models/gesture_recognizer.task {DATA}/{stamp}_hg*_hagrid_*')


if __name__ == '__main__':
    main()
