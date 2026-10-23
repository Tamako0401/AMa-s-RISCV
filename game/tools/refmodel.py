#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""显示硬件的参考模型: 照 C 游戏存下的帧 (build/touhou --dump) 算出硬件该出的画面, 并数每行要用几拍。

用法:
  game/tools/refmodel.py render <帧.jsonl> [--frame 帧号] [-o 输出.png]
      画一帧 (默认是最忙的那帧), 存成 1280x720 的 PNG。以后 RTL 仿真的截图要和它逐像素一样。
  game/tools/refmodel.py cost <帧.jsonl> ... [--mhz 50] [--setup 4] [--affine 1] [--max-objects 0] [-o 图.png]
      数每条逻辑行要几拍, 和这一行的时间比; 列出最忙的帧。-o: 把最忙那帧和每行拍数画在一起。

这里写下的算法就是硬件的规格 (C 的 SDL 后端只求看着像, 不求逐像素一致):

画面 640x360, 每点 RGB565, 从下到上:
  1. 底色; 游戏区 (clip0 <= x < clip1) 里是背景: 画面点 (x, y) 取背景点 ((x + 卷动x) & 511, (y + 卷动y) & 511),
     落在 8x8 图块上; 图块的点透明就露出底色。
  2. 摄像头小窗 160x120 (不透明, 不受 clip 影响)。
  3. 精灵, 按表的顺序, 后画的在上面。图案边长 S, 中心 (x, y)。
     不旋转: 外框 S x S, 左上角 (x - S/2, y - S/2)。
     旋转缩放 (AFFINE): 外框 D x D, D = S * scale / 16 * 3 / 2 (整数除法), 中心同上。
       外框里的点 (px, py) 用半像素坐标 dx = 2 (px - x) + 1, dy = 2 (py - y) + 1, 反算图案坐标 (Q12, 半像素):
         pa = cos * inv >> 14, pb = sin * inv >> 14         (cos, sin: 一圈 256 档, Q14 查表; inv = 65536 / scale 取整)
         u2 = pa * dx + pb * dy + (S << 12),  v2 = -pb * dx + pa * dy + (S << 12)
         图案点 (u2 >> 13, v2 >> 13), 出了 0..S-1 就不画。硬件里沿一行每走一点 u2 += 2 pa, v2 -= 2 pb, 结果一样。
     翻转在图案坐标上做 (u = S-1-u); 透明色 (0xF81F) 不画; CLIP 的精灵只画 clip 以内。
     混合 (每个通道按自己的位数 5/6/5 算):
       不透明: 新 = 图;  ALPHA: 新 = (图 * a + 底 * (16 - a)) >> 4;
       ADD: 新 = min(底 + 图', 最大值), 图' = ALPHA 时 (图 * a) >> 4, 否则 = 图。
  4. 整体混色 (fade): 新 = (原 * (16 - l) + 颜色 * l) >> 4。
输出放大 2 倍成 1280x720, 再盖文字层 (8x16 一格, 字形的点用 16 色调色板, 别的点透明)。
RGB565 -> RGB888 时高位补到低位 (r8 = r5 << 3 | r5 >> 2), HDMI 芯片收到的就是这个。
"""

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import assets  # noqa: E402  # pyright: ignore[reportMissingImports]  同一份图案和字库

W, H = 640, 360
TRANSPARENT = assets.TRANSPARENT
ALPHA, ADD, FLIP_X, FLIP_Y, AFFINE, CLIP = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
CGA = [(0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170), (170, 0, 0), (170, 0, 170), (170, 85, 0), (170, 170, 170),
       (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255), (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255)]

# 硬件的查找表: sin 一圈 256 档 Q14; 1/scale (scale 16 = 原大) Q12
SIN = [round(16384 * math.sin(2 * math.pi * a / 256)) for a in range(256)]
INV = [0] + [round(65536 / s) for s in range(1, 256)]

MAX = np.array([31, 63, 31])  # RGB565 各通道最大值


def split(c):
    """RGB565 (数组) -> (..., 3) 的 r5 g6 b5。"""
    c = np.asarray(c, np.int32)
    return np.stack([c >> 11, (c >> 5) & 63, c & 31], -1)


def to_rgb888(ch):
    r, g, b = ch[..., 0], ch[..., 1], ch[..., 2]
    return np.stack([r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2], -1).astype(np.uint8)


class Assets:
    def __init__(self):
        self.images = [assets.rgb565(assets.load(name, size, make)).astype(np.int32) for name, size, make in assets.IMAGES]
        self.font = assets.font()


def read_dump(path):
    lines = Path(path).read_text().splitlines()
    return json.loads(lines[0]), [json.loads(line) for line in lines[1:]]


def camera_placeholder():
    """存帧里没有摄像头画面: 用灰色渐变代替 (只占位置, 颜色无所谓)。"""
    y, x = np.mgrid[:120, :160]
    gray = (40 + x // 4 + y // 4).astype(np.int32)
    return np.stack([gray >> 3, gray >> 2, gray >> 3], -1)


def sprite_box(spr, size):
    """外框: 左上角和边长 (画面坐标)。"""
    x, y, _, flags, _, _, scale = spr
    d = size * scale // 16 * 3 // 2 if flags & AFFINE else size
    return x - d // 2, y - d // 2, d


def sample(spr, img, px, py):
    """外框里的点 (px, py 数组) -> 图案颜色; 不画的点是 -1。"""
    x, y, _, flags, _, angle, scale = spr
    size = img.shape[0]
    if flags & AFFINE:
        if scale == 0:
            return np.full(px.shape, -1)
        cos, sin = SIN[(angle + 64) & 255], SIN[angle]
        pa, pb = cos * INV[scale] >> 14, sin * INV[scale] >> 14
        dx, dy = 2 * (px - x) + 1, 2 * (py - y) + 1
        u = (pa * dx + pb * dy + (size << 12)) >> 13
        v = (-pb * dx + pa * dy + (size << 12)) >> 13
    else:
        u, v = px - (x - size // 2), py - (y - size // 2)
    if flags & FLIP_X:
        u = size - 1 - u
    if flags & FLIP_Y:
        v = size - 1 - v
    inside = (u >= 0) & (u < size) & (v >= 0) & (v < size)
    color = np.where(inside, img[np.clip(v, 0, size - 1), np.clip(u, 0, size - 1)], TRANSPARENT)
    return np.where(color == TRANSPARENT, -1, color)


def render(header, frame, art, max_objects=0, camera=None):
    """画一帧: 返回 360x640x3 的 r5 g6 b5 (放大和文字之前)。max_objects > 0: 每行最多画这么多个对象, 多的丢掉 (硬件的上限)。"""
    out = np.zeros((H, W, 3), np.int32)
    out[...] = split(header['backdrop'])

    # 背景
    clip0, clip1 = header['clip']
    sx, sy = frame['scroll']
    tiles = np.array(header['map']).reshape(64, 64)
    y, x = np.mgrid[:H, clip0:clip1]
    bx, by = (x + sx) & 511, (y + sy) & 511
    tile = tiles[by >> 3, bx >> 3]
    color = np.zeros(tile.shape, np.int32)
    for t in np.unique(tile):
        sel = tile == t
        color[sel] = art.images[t][(by[sel] & 7), (bx[sel] & 7)]
    region = out[:, clip0:clip1]
    region[color != TRANSPARENT] = split(color[color != TRANSPARENT])

    # 摄像头小窗
    on, wx, wy = header['window']
    if on:
        cam = camera if camera is not None else camera_placeholder()
        x0, y0, x1, y1 = max(wx, 0), max(wy, 0), min(wx + 160, W), min(wy + 120, H)
        if x0 < x1 and y0 < y1:
            out[y0:y1, x0:x1] = cam[y0 - wy : y1 - wy, x0 - wx : x1 - wx]

    # 精灵
    used = np.zeros(H, np.int32)  # 每行已经画了几个对象
    for spr in frame['sprites']:
        _, _, image, flags, alpha, _, _ = spr
        if image >= len(art.images):
            continue
        img = art.images[image]
        left, top, d = sprite_box(spr, img.shape[0])
        y0, y1 = max(top, 0), min(top + d, H)
        if y0 >= y1:
            continue
        rows = np.arange(y0, y1)
        if max_objects:
            ok = used[rows] < max_objects
            used[rows] += 1
            rows = rows[ok]
            if len(rows) == 0:
                continue
        lo, hi = (clip0, clip1) if flags & CLIP else (0, W)
        x0, x1 = max(left, lo), min(left + d, hi)
        if x0 >= x1:
            continue
        py, px = np.meshgrid(rows, np.arange(x0, x1), indexing='ij')
        color = sample(spr, img, px, py)
        mask = color >= 0
        if not mask.any():
            continue
        src = split(np.where(mask, color, 0))
        dst = out[py, px]
        a = alpha if flags & ALPHA else 16
        if flags & ADD:
            new = np.minimum(dst + (src * a >> 4), MAX)
        elif a < 16:
            new = (src * a + dst * (16 - a)) >> 4
        else:
            new = src
        out[py[mask], px[mask]] = new[mask]

    fade_color, level = frame.get('fade', [0, 0])
    if level:
        out = (out * (16 - level) + split(fade_color) * level) >> 4
    return out


def compose(header, frame, art, max_objects=0):
    """完整输出: 放大 2 倍 + 文字层, 1280x720 RGB888。"""
    big = np.repeat(np.repeat(render(header, frame, art, max_objects), 2, 0), 2, 1)
    rgb = to_rgb888(big)
    font = art.font
    for row, (chars, colors) in enumerate(zip(frame.get('text', []), frame.get('text_color', []))):
        for col, ch in enumerate(chars):
            code = ord(ch)
            if code <= 32 or code >= 128:
                continue
            bits = np.unpackbits(font[code][:, None], axis=1).astype(bool)  # 16 x 8
            cell = rgb[row * 16 : row * 16 + 16, col * 8 : col * 8 + 8]
            cell[bits] = to_rgb888(split(assets_rgb565(CGA[int(colors[col], 16)])))
    return rgb


def assets_rgb565(rgb):
    r, g, b = rgb
    return (r >> 3) << 11 | (g >> 2) << 5 | (b >> 3)


# ---- 每行几拍 ----


def line_cycles(header, frame, art, setup, affine_rate, bg_cycles):
    """每条逻辑行要几拍。代价模型 (都是假设, 改参数比较):
    背景 + 小窗: 一拍 8 点, 640 点 bg_cycles 拍;
    每个和这一行相交的对象: 准备 setup 拍 (读属性、算起点), 再画:
      不旋转: 一拍写行缓存的一个 8 点格子, 碰到几个格子就几拍;
      旋转: 一拍 affine_rate 个点 (逐点采样)。"""
    clip0, clip1 = header['clip']
    cycles = np.full(H, bg_cycles, np.int64)
    objects = np.zeros(H, np.int64)
    for spr in frame['sprites']:
        image, flags = spr[2], spr[3]
        if image >= len(art.images):
            continue
        left, top, d = sprite_box(spr, art.images[image].shape[0])
        y0, y1 = max(top, 0), min(top + d, H)
        if y0 >= y1:
            continue
        lo, hi = (clip0, clip1) if flags & CLIP else (0, W)
        x0, x1 = max(left, lo), min(left + d, hi)
        if x0 >= x1:
            draw = 0
        elif flags & AFFINE:
            draw = -(-(x1 - x0) // affine_rate)
        else:
            draw = ((x1 - 1) >> 3) - (x0 >> 3) + 1
        cycles[y0:y1] += setup + draw
        objects[y0:y1] += 1
    return cycles, objects


def cmd_render(args):
    header, frames = read_dump(args.dump)
    art = Assets()
    frame = pick(header, frames, art, args.frame)
    rgb = compose(header, frame, art, args.max_objects)
    out = args.output or f'{Path(args.dump).stem}-{frame["frame"]}.png'
    Image.fromarray(rgb).save(out)
    print(f'第 {frame["frame"]} 帧, {len(frame["sprites"])} 个精灵 -> {out}')


def pick(header, frames, art, number):
    if number is not None:
        for f in frames:
            if f['frame'] == number:
                return f
        sys.exit(f'没有第 {number} 帧; 有: {[f["frame"] for f in frames][:20]} ...')
    return max(frames, key=lambda f: line_cycles(header, f, art, 4, 1, 80)[0].max())


def cmd_cost(args):
    art = Assets()
    budget = int(args.mhz * 1e6 * 2 * 1650 / 74.25e6)  # 一条逻辑行 = 两条 720p 物理行 (各 1650 个像素时钟)
    print(f'参数: {args.mhz} MHz, 一条逻辑行 {budget} 拍; 每对象准备 {args.setup} 拍, 旋转一拍 {args.affine} 点, 背景 {args.bg} 拍')
    print(f'{"文件":<24} {"帧数":>4} {"最忙帧":>6} {"最忙行拍数":>10} {"占比":>6} {"最多对象/行":>10}')
    worst = None
    for path in args.dump:
        header, frames = read_dump(path)
        results = [(f, *line_cycles(header, f, art, args.setup, args.affine, args.bg)) for f in frames]
        f, cycles, _ = max(results, key=lambda r: r[1].max())
        peak = int(cycles.max())
        most = max(int(objects.max()) for _, _, objects in results)
        print(f'{Path(path).name:<24} {len(frames):>4} {f["frame"]:>6} {peak:>10} {peak / budget:>6.0%} {most:>10}')
        if worst is None or peak > worst[0]:
            worst = (peak, header, f, cycles, path)
    if args.output and worst:
        plot(args, worst, budget, art)


def plot(args, worst, budget, art):
    """左边是那一帧 (1280x720), 右边是每条逻辑行的拍数, 竖线是预算。"""
    peak, header, frame, cycles, path = worst
    rgb = compose(header, frame, art)
    chart_w = 300
    img = Image.new('RGB', (1280 + chart_w, 720), (20, 20, 24))
    img.paste(Image.fromarray(rgb), (0, 0))
    draw = ImageDraw.Draw(img)
    scale = (chart_w - 20) / max(budget, peak)
    for y, c in enumerate(cycles):
        color = (220, 80, 80) if c > budget else (90, 170, 230)
        draw.rectangle([1280, y * 2, 1280 + int(c * scale), y * 2 + 1], fill=color)
    x = 1280 + int(budget * scale)
    draw.line([x, 0, x, 719], fill=(240, 240, 240))
    draw.text((1284, 4), f'{Path(path).name} #{frame["frame"]}', fill=(240, 240, 240))
    draw.text((1284, 18), f'peak {peak} / budget {budget}', fill=(240, 240, 240))
    img.save(args.output)
    print(f'最忙的一帧和每行拍数 -> {args.output}')


def main():
    parser = argparse.ArgumentParser(usage=__doc__)
    sub = parser.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('render')
    r.add_argument('dump')
    r.add_argument('--frame', type=int)
    r.add_argument('--max-objects', type=int, default=0)
    r.add_argument('-o', '--output')
    c = sub.add_parser('cost')
    c.add_argument('dump', nargs='+')
    c.add_argument('--mhz', type=float, default=50)
    c.add_argument('--setup', type=int, default=4)
    c.add_argument('--affine', type=int, default=1)
    c.add_argument('--bg', type=int, default=80)
    c.add_argument('-o', '--output')
    args = parser.parse_args()
    {'render': cmd_render, 'cost': cmd_cost}[args.cmd](args)


if __name__ == '__main__':
    main()
