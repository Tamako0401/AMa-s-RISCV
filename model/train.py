#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "opencv-python", "torch"]
# ///
"""训练手势小网络 (handnet.py): MediaPipe 的标注 (label.py) 当答案。每几轮在验证集上打印指标, 最后存模型。

用法: model/train.py <训练用的 session 目录...> --val <验证用的 session 目录...>
        [--size 160] [--width 8] [--epochs 30] [--name 名字]
  --size: 输入宽度 (80 / 160 / 320), 高是宽的 3/4; 从 640x480 原图按块平均缩小, 和硬件一样。
  --width: 网络宽度, 第一层的通道数, 后面是它的 2、4 倍。
  验证集只用来评估, 不参与训练。以后要按人分: 验证集里的人不出现在训练集。
存到 model/runs/<名字>.pt。第一次读 session 会把缩小后的图存成 session 目录下的 small_<宽>.npy, 以后直接读。

用哪些帧 (见 docs/hand-model.md):
  - 老师找到手的帧: 正样本, 手心位置和手势 (手势是 -1 的只学位置)。
  - "应该没有手" 的段 (no_hand、face) 里老师也没找到手的帧: 负样本。
  - 其余段里老师没找到手的帧不用: 可能是老师漏检, 当负样本会教错。
"""

import argparse
import json
import random
import time
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F

from handnet import STRIDE, HandNet, decode, macs, save, shrink

FIST, IGNORE = 0, -1  # 手势编号, 同 label.py (不 import 它, 省得训练也要装 MediaPipe)

RUNS = Path(__file__).parent / 'runs'
SIGMA = 1.0  # 热力图上手心那团高斯的大小, 单位是格
THRESHOLD = 0.5  # 热力图分数超过它算找到手
FAR = 10  # 误差超过几个点 (160x120 下) 算 "跑到别处了"


def load_session(session, w):
    """读一个 session: 缩小后的图、每帧最多两只手的手心和手势、段名。按上面的规则筛帧。"""
    labels = np.load(session / 'labels.npz')
    expect = json.loads((session / 'meta.json').read_text()).get('expect', {})
    cache = session / f'small_{w}.npy'
    if cache.exists():
        images = np.load(cache)
    else:
        images = np.stack([shrink(cv2.imread(str(session / f)), w) for f in labels['files']])
        np.save(cache, images)
    should_be_empty = np.array([expect.get(s) == 'none' for s in labels['segment']])
    found = labels['hands'] > 0
    keep = (found & ~should_be_empty) | (~found & should_be_empty)
    return images[keep], labels['center'][keep], labels['gesture'][keep], labels['segment'][keep]


def load_all(sessions, w):
    parts = [load_session(Path(s), w) for s in sessions]
    return [np.concatenate(x) for x in zip(*parts)]


def augment(image, centers):
    """随机改一下图, 让模型不依赖这台摄像头的颜色和位置: 左右翻转、平移缩放、白平衡、亮度对比度、噪声、模糊。"""
    h, w = image.shape[:2]
    # 左右翻转: 右手变成左手, 录得少的那只手也能学到
    if random.random() < 0.5:
        image = image[:, ::-1]
        centers = centers * [-1, 1] + [1, 0]
    # 平移缩放; 手心被移出画面就不做这一步
    s = random.uniform(0.85, 1.15)
    tx, ty = random.uniform(-0.1, 0.1) * w, random.uniform(-0.1, 0.1) * h
    moved = (centers * [w, h] - [w / 2, h / 2]) * s + [w / 2 + tx, h / 2 + ty]
    valid = ~np.isnan(moved[:, 0])
    if ((moved[valid] >= 0) & (moved[valid] < [w, h])).all():
        m = np.float32([[s, 0, (1 - s) * w / 2 + tx], [0, s, (1 - s) * h / 2 + ty]])
        image = cv2.warpAffine(image, m, (w, h), borderMode=cv2.BORDER_REPLICATE)
        centers = moved / [w, h]
    # 颜色: 每个通道乘一个系数 (白平衡), 再整体改对比度和亮度
    x = image.astype(np.float32) * np.random.uniform(0.8, 1.2, 3)
    x = (x - 128) * random.uniform(0.7, 1.3) + 128 + random.uniform(-30, 30)
    x += np.random.normal(0, random.uniform(0, 6), x.shape)
    image = np.clip(x, 0, 255).astype(np.uint8)
    if random.random() < 0.3:
        image = cv2.GaussianBlur(image, (3, 3), 0)
    return image, centers


def targets(centers, gestures, gw, gh):
    """一帧的答案, 和网络输出一样按格排: 热力图、格内偏移、手势, 以及偏移和手势在哪些格算数。"""
    heat = np.zeros((gh, gw), np.float32)
    offset = np.zeros((2, gh, gw), np.float32)
    gesture = np.zeros((gh, gw), np.float32)
    has_offset = np.zeros((gh, gw), np.float32)
    has_gesture = np.zeros((gh, gw), np.float32)
    ys, xs = np.mgrid[0:gh, 0:gw]
    for (x, y), g in zip(centers, gestures):
        if np.isnan(x):
            continue
        gx, gy = x * gw, y * gh
        ix, iy = min(int(gx), gw - 1), min(int(gy), gh - 1)
        # 手心所在格是 1, 周围按高斯往下降 (CenterNet 的做法): 附近的格算 "差一点", 少罚一些
        heat = np.maximum(heat, np.exp(-((xs - ix) ** 2 + (ys - iy) ** 2) / (2 * SIGMA**2)))
        offset[:, iy, ix] = gx - ix, gy - iy
        has_offset[iy, ix] = 1
        if g != IGNORE:
            gesture[iy, ix] = g == FIST
            has_gesture[iy, ix] = 1
    return heat.astype(np.float32), offset, gesture, has_offset, has_gesture  # MPS 不支持 float64


class Frames(torch.utils.data.Dataset):
    def __init__(self, data, train):
        self.images, self.centers, self.gestures, _ = data
        self.train = train

    def __len__(self):
        return len(self.images)

    def __getitem__(self, i):
        image, centers = self.images[i], self.centers[i]
        if self.train:
            image, centers = augment(image, centers)
        h, w = image.shape[:2]
        answer = targets(centers, self.gestures[i], w // STRIDE, h // STRIDE)
        return (torch.from_numpy(np.ascontiguousarray(image)).permute(2, 0, 1), *map(torch.from_numpy, answer))


def focal(pred, heat):
    """热力图损失 (CenterNet 版 focal loss): 背景格太多, 降低已经判对的简单格的权重; 手心附近的格少罚。"""
    p = torch.sigmoid(pred).clamp(1e-4, 1 - 1e-4)
    pos = heat == 1
    pos_loss = (torch.log(p) * (1 - p) ** 2)[pos].sum()
    neg_loss = (torch.log(1 - p) * p**2 * (1 - heat) ** 4)[~pos].sum()
    return -(pos_loss + neg_loss) / pos.sum().clamp(min=1)


def loss_of(out, heat, offset, gesture, has_offset, has_gesture):
    l_heat = focal(out[:, 0], heat)
    l_offset = (F.l1_loss(torch.sigmoid(out[:, 1:3]), offset, reduction='none').sum(1) * has_offset).sum()
    l_offset = l_offset / has_offset.sum().clamp(min=1)
    l_gesture = F.binary_cross_entropy_with_logits(out[:, 3], gesture, reduction='none') * has_gesture
    l_gesture = l_gesture.sum() / has_gesture.sum().clamp(min=1)
    return l_heat + l_offset + l_gesture


def evaluate(model, data, device):
    """在验证集上算指标, 按段打表。误差单位统一是 160x120 画面里的点, 不同输入尺寸可以直接比。"""
    images, centers, gestures, segments = data
    model.eval()
    results = []
    with torch.no_grad():
        for i in range(0, len(images), 256):
            batch = torch.from_numpy(images[i : i + 256]).permute(0, 3, 1, 2).to(device)
            results += [decode(o) for o in model(batch).cpu()]
    model.train()

    rows = {}
    for (score, x, y, fist), c, g, seg in zip(results, centers, gestures, segments):
        row = rows.setdefault(seg, {'pos': 0, 'miss': 0, 'err': [], 'neg': 0, 'false': 0, 'gest': 0, 'right': 0})
        hands = ~np.isnan(c[:, 0])
        if not hands.any():
            row['neg'] += 1
            row['false'] += score >= THRESHOLD
            continue
        row['pos'] += 1
        if score < THRESHOLD:
            row['miss'] += 1
            continue
        dist = np.hypot((c[hands, 0] - x) * 160, (c[hands, 1] - y) * 120)  # 离哪只手近就和哪只比
        row['err'].append(dist.min())
        k = np.flatnonzero(hands)[dist.argmin()]
        if g[k] != IGNORE:
            row['gest'] += 1
            row['right'] += (fist > 0.5) == (g[k] == FIST)

    def line(name, r):
        e = np.array(r['err'])
        pos = f'{r["miss"] / r["pos"]:>6.0%}' if r['pos'] else f'{"-":>6}'
        err = f'{np.median(e):>6.1f}{np.percentile(e, 95):>6.1f}{np.mean(e > FAR):>6.0%}' if len(e) else f'{"-":>6}' * 3
        neg = f'{r["false"] / r["neg"]:>6.0%}' if r['neg'] else f'{"-":>6}'
        gest = f'{r["right"] / r["gest"]:>6.0%}' if r['gest'] else f'{"-":>6}'
        return f'  {name:<12}{r["pos"]:>6}{pos}{err}{r["neg"]:>6}{neg}{gest}'

    print(f'  {"段":<11}{"有手帧":>3}{"漏检":>4}{"中位":>4}{"P95":>6}{">10点":>5}{"无手帧":>3}{"误检":>4}{"手势对":>3}')
    for seg, r in rows.items():
        print(line(seg, r))
    total = {k: sum((r[k] for r in rows.values()), [] if k == 'err' else 0) for k in next(iter(rows.values()))}
    print(line('合计', total))


def main():
    parser = argparse.ArgumentParser(usage=__doc__)
    parser.add_argument('sessions', nargs='+')
    parser.add_argument('--val', nargs='+', required=True)
    parser.add_argument('--size', type=int, default=160)
    parser.add_argument('--width', type=int, default=8)
    parser.add_argument('--epochs', type=int, default=30)
    parser.add_argument('--name')
    args = parser.parse_args()
    name = args.name or f'w{args.width}_{args.size}_{time.strftime("%m%d_%H%M")}'

    train_data = load_all(args.sessions, args.size)
    val_data = load_all(args.val, args.size)
    print(f'训练 {len(train_data[0])} 帧, 验证 {len(val_data[0])} 帧, 输入 {args.size}x{args.size * 3 // 4}')

    device = 'mps' if torch.backends.mps.is_available() else 'cpu'
    model = HandNet(args.width)
    n_macs, n_params = macs(model, args.size, args.size * 3 // 4)
    print(f'网络宽度 {args.width}: 每帧 {n_macs / 1e6:.2f} M 次乘加, {n_params} 个参数; 在 {device} 上训练')
    model.to(device).train()

    loader = torch.utils.data.DataLoader(Frames(train_data, True), batch_size=64, shuffle=True, drop_last=True)
    optimizer = torch.optim.AdamW(model.parameters(), lr=3e-3, weight_decay=1e-4)
    schedule = torch.optim.lr_scheduler.OneCycleLR(optimizer, 3e-3, total_steps=args.epochs * len(loader))
    for epoch in range(1, args.epochs + 1):
        start, losses = time.time(), []
        for batch in loader:
            image, *answer = (x.to(device) for x in batch)
            loss = loss_of(model(image), *answer)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            schedule.step()
            losses.append(loss.item())
        print(f'第 {epoch} 轮: 损失 {np.mean(losses):.3f} ({time.time() - start:.0f} 秒)')
        if epoch % 10 == 0 or epoch == args.epochs:
            evaluate(model, val_data, device)

    RUNS.mkdir(exist_ok=True)
    save(RUNS / f'{name}.pt', model.cpu(), args.width, args.size)
    print(f'存到 {RUNS / name}.pt')


if __name__ == '__main__':
    main()
