#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""显示硬件的参考模型: 照 C 游戏存下的帧 (build/touhou --dump) 算出硬件该出的画面, 并数每行要用几拍。

用法:
  game/tools/refmodel.py render <帧.jsonl> [--frame 帧号] [--blade-layer] [-o 输出.png]
      画一帧 (默认是最忙的那帧), 存成 1280x720 的 PNG。以后 RTL 仿真的截图要和它逐像素一样。
  game/tools/refmodel.py cost <帧.jsonl> ... [--mhz 50] [--setup 4] [--affine 1] [--max-objects 0] [-o 图.png]
      数每条逻辑行要几拍, 和这一行的时间比; 列出最忙的帧。-o: 把最忙那帧和每行拍数画在一起。
  game/tools/refmodel.py colors <帧.jsonl> ... [--frame 帧号] [--shaded] [-o 图.png]
      图案存成 RGB565 / 256 色共用调色板 / 每张 16 色, 画同一帧比一比 (每个文件取发光最多的地方放大)。
  game/tools/refmodel.py memory [--sprites 512] [--line-objects 128] [--patterns-kb 0] [--pattern-bits 16]
      列出整个 SoC 要的片上 RAM, 按块 RAM 的拼法算要几块, 和 50K / 100K 两块板比。

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

IMG_RING = [name for name, _, _ in assets.IMAGES].index('ring')
IMG_BLADE = [name for name, _, _ in assets.IMAGES].index('blade')
MAX = np.array([31, 63, 31])  # RGB565 各通道最大值


def split(c):
    """RGB565 (数组) -> (..., 3) 的 r5 g6 b5。"""
    c = np.asarray(c, np.int32)
    return np.stack([c >> 11, (c >> 5) & 63, c & 31], -1)


def to_rgb888(ch):
    r, g, b = ch[..., 0], ch[..., 1], ch[..., 2]
    return np.stack([r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2], -1).astype(np.uint8)


class Assets:
    """colors: 0 = 图案存 RGB565; 256 = 所有图案共用一个 256 色调色板 (每点 8 位); 16 = 每张图案自己 16 色 (每点 4 位)。
    调色板里存的也是 RGB565, 查完表照样按 RGB565 混合, 所以只有图案本身的颜色变了。"""

    def __init__(self, colors=0, shaded=False):
        loaded = [(name, assets.load(name, size, make)) for name, size, make in assets.IMAGES]
        if shaded:
            loaded = [(name, img if name in GLOWS or img.shape[0] == 8 else shade(img)) for name, img in loaded]
        self.images = [assets.rgb565(img).astype(np.int32) for _, img in loaded]
        self.font = assets.font()
        if colors == 256:
            self.images = quantize(self.images, 255)  # 留一个编号给透明
        elif colors == 16:
            self.images = [quantize([img], 15)[0] for img in self.images]


GLOWS = {'spark', 'ring', 'juice_red', 'juice_orange', 'juice_green', 'blade'}  # 本来就是渐变, 不另加光照


def shade(img):
    """占位图是几块纯色, 测不出调色板够不够。给它加上球面光照 (左上来光, 带高光), 颜色变得像正式素材一样多。"""
    size = img.shape[0]
    y, x = (np.mgrid[:size, :size] - (size - 1) / 2) / (size / 2)
    z = np.sqrt(np.clip(1 - x * x - y * y, 0, 1))
    light = np.array([-0.5, -0.6, 0.62])
    light /= np.linalg.norm(light)
    lambert = np.clip(x * light[0] + y * light[1] + z * light[2], 0, 1)
    k = 0.35 + 0.8 * lambert + 0.5 * lambert ** 20
    out = img.copy()
    out[..., :3] = np.clip(img[..., :3] * k[..., None], 0, 255).astype(np.uint8)
    return out


def quantize(images, n):
    """这些图案不透明的点一起选出 n 个颜色 (中位切分), 每个点换成最近的那个。"""
    opaque = np.concatenate([img[img != TRANSPARENT] for img in images])
    if len(np.unique(opaque)) <= n:
        return images
    strip = Image.fromarray(to_rgb888(split(opaque))[None])
    pal_img = strip.quantize(colors=n, method=Image.Quantize.MEDIANCUT)
    pal = np.array(pal_img.getpalette()[: 3 * n]).reshape(-1, 3)
    pal565 = (pal[:, 0] >> 3) << 11 | (pal[:, 1] >> 2) << 5 | (pal[:, 2] >> 3)
    out = []
    for img in images:
        mask = img != TRANSPARENT
        new = img.copy()
        if mask.any():
            rgb = Image.fromarray(to_rgb888(split(img[mask]))[None])
            idx = np.asarray(rgb.quantize(palette=pal_img, dither=Image.Dither.NONE))[0]
            new[mask] = pal565[idx]
        out.append(new)
    return out


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


def compose(header, frame, art, max_objects=0, blade_layer=False):
    """完整输出: 放大 2 倍 + 文字层, 1280x720 RGB888。
    blade_layer: 试验刀光层 (还没定做不做): 刀光的光点精灵不画, 改成在 1280x720 上画一条平滑、带软边的线。"""
    blade = []
    if blade_layer:
        blade = [s for s in frame['sprites'] if s[2] == IMG_BLADE]
        frame = {**frame, 'sprites': [s for s in frame['sprites'] if s[2] != IMG_BLADE]}
    big = np.repeat(np.repeat(render(header, frame, art, max_objects), 2, 0), 2, 1)
    rgb = to_rgb888(big)
    if blade:
        draw_blade_layer(rgb, blade)
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


def draw_blade_layer(rgb, dots):
    """刀光层的样子: 光点按表里的顺序 (新 -> 旧) 连成折线, 在 1280x720 上按到线的距离算亮度:
    中间实、边缘 1 点宽的过渡 (抗锯齿), 外面一圈淡的光晕; 越旧越细越淡。加到画面上 (加法)。"""
    pts = [(2 * s[0] + 1, 2 * s[1] + 1, s[4]) for s in dots]
    light = np.zeros(rgb.shape[:2])
    for (ax, ay, aa), (bx, by, ba) in zip(pts, pts[1:]):
        if abs(ax - bx) + abs(ay - by) > 80:  # 不是同一条刀光
            continue
        age = (aa + ba) / 32  # 1 = 最新
        hw = 1 + 3 * age  # 半宽 (1280x720 的点)
        r = int(hw * 3) + 2
        x0, x1 = max(min(ax, bx) - r, 0), min(max(ax, bx) + r, 1280)
        y0, y1 = max(min(ay, by) - r, 0), min(max(ay, by) + r, 720)
        if x0 >= x1 or y0 >= y1:
            continue
        y, x = np.mgrid[y0:y1, x0:x1]
        ex, ey = bx - ax, by - ay
        t = np.clip(((x - ax) * ex + (y - ay) * ey) / max(ex * ex + ey * ey, 1), 0, 1)
        d = np.hypot(x - (ax + t * ex), y - (ay + t * ey))
        core = np.clip(hw - d + 0.5, 0, 1)
        halo = np.clip(1 - d / (hw * 3), 0, 1) * 0.35
        light[y0:y1, x0:x1] = np.maximum(light[y0:y1, x0:x1], np.maximum(core, halo) * age)
    add = light[..., None] * np.array([210, 240, 255])
    rgb[...] = np.clip(rgb + add, 0, 255).astype(np.uint8)


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
    rgb = compose(header, frame, art, args.max_objects, args.blade_layer)
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


def cmd_colors(args):
    """每个文件: 取一帧, 找加法混合 (发光) 的对象最密的地方, 三种图案格式各画一遍, 放大 3 倍排成一行。"""
    variants = [(0, 'RGB565, 16 bit'), (256, 'shared 256 colors, 8 bit'), (16, '16 colors per image, 4 bit')]
    arts = [Assets(c, args.shaded) for c, _ in variants]
    print('图案不同颜色数:', len(np.unique(np.concatenate([i[i != TRANSPARENT] for i in arts[0].images]))),
          '(加了光照)' if args.shaded else '(占位图)')
    cw, ch, zoom = 220, 140, 3
    rows = []
    for path in args.dump:
        header, frames = read_dump(path)
        if args.frame is not None:
            frame = pick(header, frames, arts[0], args.frame)
        else:  # 发光的对象最多的那帧
            frame = max(frames, key=lambda f: sum(s[3] & ADD and s[6] for s in f['sprites']) + 50 * sum(s[2] == IMG_RING for s in f['sprites']))
        glow = [s for s in frame['sprites'] if s[3] & ADD] or frame['sprites']
        cx = int(np.median([s[0] for s in glow]))
        cy = int(np.median([s[1] for s in glow]))
        x0, y0 = min(max(cx - cw // 2, 0), W - cw), min(max(cy - ch // 2, 0), H - ch)
        base = None
        row = Image.new('RGB', (len(variants) * (cw * zoom + 10), ch * zoom + 24), (30, 30, 34))
        draw = ImageDraw.Draw(row)
        for i, (art, (_, name)) in enumerate(zip(arts, variants)):
            ch565 = render(header, frame, art)
            if base is None:
                base = ch565
            err = np.abs(to_rgb888(ch565).astype(int) - to_rgb888(base).astype(int)).max(-1)
            crop = to_rgb888(ch565[y0 : y0 + ch, x0 : x0 + cw])
            row.paste(Image.fromarray(crop).resize((cw * zoom, ch * zoom), Image.Resampling.NEAREST), (i * (cw * zoom + 10), 24))
            draw.text((i * (cw * zoom + 10) + 4, 4), f'{name}: {(err > 24).mean():.1%} px differ by >24', fill=(240, 240, 240))
            print(f'{Path(path).name} #{frame["frame"]} {name:<28} 和 RGB565 差 >24 的点 {(err > 24).mean():.2%}, 最大差 {err.max()}')
        rows.append(row)
    out = Image.new('RGB', (rows[0].width, sum(r.height for r in rows)))
    y = 0
    for r in rows:
        out.paste(r, (0, y))
        y += r.height
    output = args.output or 'colors.png'
    out.save(output)
    print(f'-> {output}')


# ---- 存储 ----

# 盘古的块 RAM (DRM18K) 一块 18 Kb, 可以拼成这些 深度 x 宽度 (简单双口)
DRM_CONFIGS = [(16384, 1), (8192, 2), (4096, 4), (2048, 9), (1024, 18), (512, 36)]
BOARDS = [('50K (MES50HP, 现在)', 134), ('100K (PG2L100H, 选型表, 未核实)', 310)]


def drm_blocks(depth, width, pad=True):
    """一块 depth x width 的 RAM 要几个 DRM18K。pad: PDS 推断 RAM 时把深度补成 2 的幂 (vision.md 里量到的);
    手工拆成小块的 (pad=False) 不补。"""
    if pad:
        depth = 1 << (depth - 1).bit_length()
    return min(-(-depth // d) * -(-width // w) for d, w in DRM_CONFIGS)


def cmd_memory(args):
    art = Assets()
    pixels = sum(img.size for img in art.images)
    if args.patterns_kb:
        pixels = args.patterns_kb * 1024 // 2
    n, k, bits = args.sprites, args.line_objects, args.pattern_bits
    # 名字, 深度, 宽度, 份数, 补成 2 的幂?, 说明
    groups = {
        'CPU 和已有的': [
            ('指令 ROM', 16384, 32, 2, True, '64 KB; 取指口独立后 PDS 复制成两份 (实测)'),
            ('数据 RAM', 16384, 32, 1, True, '64 KB'),
            ('摄像头小窗', 19200, 8, 2, False, '160x120, 8 位色; 前台 / 后台两份, 已拆成 2048 深的小块'),
        ],
        '新显示': [
            ('图案库', pixels // 8, 8 * bits, 1, True, f'{pixels} 点, 每点 {bits} 位 ({pixels * bits // 8192} KB); 一次读 8 点, 才能一拍画 8 点'),
            *([('调色板', 256, 16, 4, True, '256 色 RGB565; 一拍查 8 个点, 真双口一份查 2 个, 所以 4 份')] if bits == 8 else []),
            ('背景图块表', 64 * 64, 10, 1, True, '64x64 格, 每格一个图案编号'),
            ('精灵表', n, 64, 2, True, f'{n} 个, 每个 64 位; 双缓冲 (CPU 写后台, 场消隐交换)'),
            ('精灵 Y 范围', n, 20, 2, True, '精灵表里上下边的副本: 每行扫一遍, 找出和下一行相交的对象'),
            ('行对象列表', k, 10, 2, True, f'每行最多 {k} 个对象的编号; 一份在写 (下一行), 一份在读 (这一行)'),
            ('行缓存', W // 8, 128, 2, True, '640 点 RGB565, 一拍读写 8 点; 一条在画, 一条在播'),
            ('文字层', 160 * 45, 12, 1, True, '160x45 格: 字符 8 位 + 颜色 4 位'),
            ('字库', 128 * 16, 8, 1, True, '128 个字, 8x16'),
        ],
        '还没定 (估计)': [
            ('手势 CNN 权重', 4096, 32, 1, True, '十几 KB (hand-model.md 的估计)'),
            ('手势 CNN 激活', 12288, 32, 1, True, '几十 KB, 按行缓存'),
            ('ILA', 4096, 32, 1, True, '赛题要求的片上逻辑分析仪, 十几 KB'),
        ],
    }
    total_bits = total_blocks = 0
    print(f'{"":<4}{"名字":<14}{"深度 x 宽度 x 份数":>20}{"净容量":>10}{"块数":>6}  说明')
    for group, rows in groups.items():
        bits = blocks = 0
        print(f'{group}')
        for name, depth, width, copies, pad, note in rows:
            b = drm_blocks(depth, width, pad) * copies
            kb = depth * width * copies / 1024
            bits += depth * width * copies
            blocks += b
            print(f'    {name:<14}{f"{depth} x {width} x {copies}":>20}{kb:>8.1f}Kb{b:>6}  {note}')
        print(f'    {"小计":<14}{"":>20}{bits / 1024:>8.1f}Kb{blocks:>6}')
        total_bits += bits
        total_blocks += blocks
    print(f'合计 {total_bits / 1024:.0f} Kb, {total_blocks} 块 DRM18K')
    for name, have in BOARDS:
        print(f'  {name}: {have} 块, 用 {total_blocks / have:.0%}' + (' (超过 80%)' if total_blocks > have * 0.8 else ''))


def main():
    parser = argparse.ArgumentParser(usage=__doc__)
    sub = parser.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('render')
    r.add_argument('dump')
    r.add_argument('--frame', type=int)
    r.add_argument('--max-objects', type=int, default=0)
    r.add_argument('--blade-layer', action='store_true', help='试验: 刀光改成 1280x720 上的平滑线 (刀光层)')
    r.add_argument('-o', '--output')
    c = sub.add_parser('cost')
    c.add_argument('dump', nargs='+')
    c.add_argument('--mhz', type=float, default=50)
    c.add_argument('--setup', type=int, default=4)
    c.add_argument('--affine', type=int, default=1)
    c.add_argument('--bg', type=int, default=80)
    c.add_argument('-o', '--output')
    k = sub.add_parser('colors')
    k.add_argument('dump', nargs='+')
    k.add_argument('--frame', type=int)
    k.add_argument('--shaded', action='store_true', help='给占位图加球面光照, 模拟颜色多的正式素材')
    k.add_argument('-o', '--output')
    m = sub.add_parser('memory')
    m.add_argument('--sprites', type=int, default=512)
    m.add_argument('--line-objects', type=int, default=128)
    m.add_argument('--patterns-kb', type=int, default=0, help='图案库按 RGB565 这么多 KB 的点数算 (默认: 现在的占位图)')
    m.add_argument('--pattern-bits', type=int, default=16, choices=[16, 8], help='图案每点几位: 16 = RGB565, 8 = 256 色调色板')
    args = parser.parse_args()
    {'render': cmd_render, 'cost': cmd_cost, 'colors': cmd_colors, 'memory': cmd_memory}[args.cmd](args)


if __name__ == '__main__':
    main()
