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
      --rtl: 按 rtl/display 实际的拍数算 (和仿真的 LINE_MAX 对得上)。
  game/tools/refmodel.py colors <帧.jsonl> ... [--frame 帧号] [--shaded] [-o 图.png]
      图案存成 RGB565 / 256 色共用调色板 / 每张 16 色, 画同一帧比一比 (每个文件取发光最多的地方放大)。
  game/tools/refmodel.py memory [--sprites 512] [--line-objects 128] [--patterns-kb 0] [--pattern-bits 16]
      列出整个 SoC 要的片上 RAM, 按块 RAM 的拼法算要几块, 和 50K / 100K 两块板比。
  game/tools/refmodel.py export (<帧.jsonl> [--frame 帧号] | --scene 名字) -o 目录
      把一帧写成 RTL 仿真要的数据: writes.hex (按 docs/display.md 的地址依次写的 地址 + 数据)、window.hex (小窗 RGB332)、
      expect.hex (期望的 1280x720 RGB888)。tests/display/ 用。
  game/tools/refmodel.py scenes -o 目录
      程序造的边界场景 (混合、翻转、clip、半出屏、旋转、每行超过上限...), 每个存成一个 <名字>.jsonl, 格式同 --dump。
  game/tools/refmodel.py firmware -o build/display_assets.c
      板上程序开机要写进显示的东西 (调色板、图案表、图案库) 写成 C 数组, 外加字库; 板上后端 game/board/ 用。
  game/tools/refmodel.py tables -o rtl/display/disp_tables.vh
      生成 RTL 的 sin、1/scale 查找表 (和这里的 SIN、INV 同一份)。

这里写下的算法就是硬件的规格 (C 的 SDL 后端只求看着像, 不求逐像素一致); 寄存器和存储布局见 docs/display.md:

图案存 8 位色号, 所有图案共用一个 256 项 RGB565 调色板, 色号 0 = 透明 (图案颜色先按 Assets(colors=256) 量化)。
画面 640x360, 每点 RGB565, 从下到上:
  1. 底色; 游戏区 (clip0 <= x < clip1) 里是背景: 画面点 (x, y) 取背景点 ((x + 卷动x) & 511, (y + 卷动y) & 511),
     落在 8x8 图块上; 图块的点透明就露出底色。
  2. 摄像头小窗 160x120 (不透明, 不受 clip 影响, 可以半出屏)。小窗存 RGB332, 扩成 RGB565 时高位补到低位:
     r5 = r3 << 2 | r3 >> 1, g6 = g3 << 3 | g3, b5 = b2 << 3 | b2 << 1 | b2 >> 1。
  3. 精灵, 按表的顺序, 后画的在上面; 表最多 512 个。x、y 是 12 位有符号数 (超出的饱和到 -2048..2047, 这时一定看不见)。
     图案编号超出图案表的不画。每行最多 LINE_OBJECTS (128) 个和这一行上下相交的对象 (不管 x 在不在屏内),
     多的按表的顺序丢掉后面的。图案边长 S, 中心 (x, y)。
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
SPRITE_MAX, LINE_OBJECTS, IMAGE_MAX = 512, 128, 1024  # 硬件精灵表、每行对象列表、图案表的容量


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

    def __init__(self, colors=256, shaded=False):
        loaded = [(name, assets.load(name, size, make)) for name, size, make in assets.IMAGES]
        if shaded:
            loaded = [(name, img if name in GLOWS or img.shape[0] == 8 else shade(img)) for name, img in loaded]
        self.images = [assets.rgb565(img).astype(np.int32) for _, img in loaded]
        self.font = assets.font()
        if colors == 256:  # 硬件的格式: palette[0] 是透明, indices 是每张图案的色号
            self.palette, self.indices = palettize(self.images, 127)  # 128~255 留给 SD 立绘
            self.images = [np.where(idx == 0, TRANSPARENT, self.palette[idx]) for idx in self.indices]
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


def palettize(images, n):
    """所有图案共用 n 个颜色 (中位切分, 颜色不多时原样用): 返回 256 项 RGB565 调色板 (0 号是透明) 和每张图案的色号。"""
    opaque = np.concatenate([img[img != TRANSPARENT] for img in images])
    colors = np.unique(opaque)
    if len(colors) <= n:
        pal565 = colors
        lookup = [np.searchsorted(colors, img) for img in images]
    else:
        strip = Image.fromarray(to_rgb888(split(opaque))[None])
        pal_img = strip.quantize(colors=n, method=Image.Quantize.MEDIANCUT)
        pal = np.array(pal_img.getpalette()[: 3 * n]).reshape(-1, 3)
        pal565 = (pal[:, 0] >> 3) << 11 | (pal[:, 1] >> 2) << 5 | (pal[:, 2] >> 3)
        lookup = []
        for img in images:
            rgb = Image.fromarray(to_rgb888(split(np.where(img == TRANSPARENT, 0, img).ravel()))[None])
            lookup.append(np.asarray(rgb.quantize(palette=pal_img, dither=Image.Dither.NONE))[0].reshape(img.shape))
    palette = np.zeros(256, np.int32)
    palette[0] = TRANSPARENT
    palette[1 : 1 + len(pal565)] = pal565
    indices = [np.where(img == TRANSPARENT, 0, idx + 1).astype(np.int32) for img, idx in zip(images, lookup)]
    return palette, indices


def read_dump(path):
    lines = Path(path).read_text().splitlines()
    return json.loads(lines[0]), [json.loads(line) for line in lines[1:]]


def camera_placeholder():
    """存帧里没有摄像头画面: 用 RGB332 的彩色渐变代替 (只占位置; 三个通道都变, 顺便查扩展的位对不对)。"""
    y, x = np.mgrid[:120, :160]
    return ((x * 8 // 160) << 5 | (y * 8 // 120) << 2 | ((x + y) >> 3) & 3).astype(np.int32)


def expand332(c):
    """RGB332 (数组) -> (..., 3) 的 r5 g6 b5, 高位补到低位。"""
    r3, g3, b2 = c >> 5, (c >> 2) & 7, c & 3
    return np.stack([r3 << 2 | r3 >> 1, g3 << 3 | g3, b2 << 3 | b2 << 1 | b2 >> 1], -1)


def sat12(v):
    return min(max(v, -2048), 2047)


def hardware_sprites(sprites):
    """硬件看到的精灵表: 最多 SPRITE_MAX 个, x、y 饱和到 12 位。"""
    return [[sat12(x), sat12(y), *rest] for x, y, *rest in sprites[:SPRITE_MAX]]


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
        cam = expand332(camera if camera is not None else camera_placeholder())
        x0, y0, x1, y1 = max(wx, 0), max(wy, 0), min(wx + 160, W), min(wy + 120, H)
        if x0 < x1 and y0 < y1:
            out[y0:y1, x0:x1] = cam[y0 - wy : y1 - wy, x0 - wx : x1 - wx]

    # 精灵
    used = np.zeros(H, np.int32)  # 每行已经画了几个对象
    for spr in hardware_sprites(frame['sprites']):
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


def rtl_line_cycles(header, frame, art):
    """rtl/display 实际的每行拍数 (和仿真的 LINE_MAX 对数用), 返回每行拍数和对象数。
    背景 + 判断小窗约 87 拍; 小窗每点一拍; 对象: 准备 5 拍 (旋转 7 拍), 和画上一个重叠;
    不旋转画 格数 + 2 拍, 旋转画 点数 + 1 拍; 外框整个在 clip 外的只花准备的拍数。"""
    clip0, clip1 = header['clip']
    on, wx, wy = header['window']
    sprites = hardware_sprites(frame['sprites'])
    boxes = []
    for spr in sprites:
        if spr[2] >= len(art.images):
            boxes.append(None)
            continue
        boxes.append(sprite_box(spr, art.images[spr[2]].shape[0]))
    cycles = np.zeros(H, np.int64)
    objects = np.zeros(H, np.int64)
    for y in range(H):
        t = 87
        if on and 0 <= y - wy < 120:
            t += max(min(wx + 160, W) - max(wx, 0), 0) + 2
        free = t  # 画的那个空下来的时刻
        n = 0
        for spr, box in zip(sprites, boxes):
            if box is None or n >= LINE_OBJECTS:
                continue
            left, top, d = box
            if not top <= y < top + d:
                continue
            n += 1
            flags = spr[3]
            lo, hi = (clip0, clip1) if flags & CLIP else (0, W)
            x0, x1 = max(left, lo), min(left + d, hi)
            ready = t + (7 if flags & AFFINE else 5)
            if x0 >= x1:
                t = ready
                continue
            start = max(ready, free)
            free = start + 1 + ((x1 - x0) + 1 if flags & AFFINE else ((x1 - 1) >> 3) - (x0 >> 3) + 3)
            t = start + 1
        cycles[y] = max(t, free) + 1
        objects[y] = n
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
    model = 'rtl/display 实际的拍数' if args.rtl else f'每对象准备 {args.setup} 拍, 旋转一拍 {args.affine} 点, 背景 {args.bg} 拍'
    print(f'参数: {args.mhz} MHz, 一条逻辑行 {budget} 拍; {model}')
    print(f'{"文件":<24} {"帧数":>4} {"最忙帧":>6} {"最忙行拍数":>10} {"占比":>6} {"最多对象/行":>10}')
    worst = None
    for path in args.dump:
        header, frames = read_dump(path)
        if args.rtl:
            results = [(f, *rtl_line_cycles(header, f, art)) for f in frames]
        else:
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


# ---- 给 RTL 仿真的数据 (地址见 docs/display.md) ----

REG, PAL, IMG, SPR, MAP, TEXT, FONT, PAT = 0x00000, 0x01000, 0x02000, 0x04000, 0x10000, 0x20000, 0x30000, 0x40000
CTRL, BACKDROP, CLIP_R, WINDOW, SCROLL, FADE, SPRITE_N, COMMIT = range(8)


def image_table(art):
    """图案库按图案顺序排, 每 8 点一个 64 位字 (左边的点在低位)。返回 [(尺寸码, 起始字)] 和所有字。"""
    table, words = [], []
    for idx in art.indices:
        size = idx.shape[0]
        table.append((size.bit_length() - 3, len(words)))
        for row in idx:
            for w in range(size // 8):
                words.append(sum(int(row[8 * w + i]) << (8 * i) for i in range(8)))
    return table, words


def sprite_words(spr):
    x, y, image, flags, alpha, angle, scale = spr
    return [
        (scale & 255) << 24 | (y & 0xFFF) << 12 | (x & 0xFFF),
        (angle & 255) << 24 | (alpha & 31) << 16 | (flags & 63) << 10 | (image & 1023),
    ]


def bus_writes(header, frame, art):
    """把这一帧要的东西按地址依次写一遍 (CPU 板上也这么写), 最后提交。"""
    out = [(PAL + 4 * i, int(c) & 0xFFFF) for i, c in enumerate(art.palette)]
    table, words = image_table(art)
    out += [(IMG + 4 * i, code << 13 | base) for i, (code, base) in enumerate(table)]
    for i, w in enumerate(words):
        out += [(PAT + 8 * i, w & 0xFFFFFFFF), (PAT + 8 * i + 4, w >> 32)]
    out += [(MAP + 4 * i, t) for i, t in enumerate(header['map'])]
    for row, (chars, colors) in enumerate(zip(frame.get('text', []), frame.get('text_color', []))):
        out += [
            (TEXT + 4 * (row * 160 + col), int(colors[col], 16) << 8 | ord(ch) & 255) for col, ch in enumerate(chars)
        ]
    out += [(FONT + 4 * (code * 16 + r), int(art.font[code][r])) for code in range(128) for r in range(16)]
    sprites = hardware_sprites(frame['sprites'])
    for i, spr in enumerate(sprites):
        w0, w1 = sprite_words(spr)
        out += [(SPR + 8 * i, w0), (SPR + 8 * i + 4, w1)]
    on, wx, wy = header['window']
    clip0, clip1 = header['clip']
    sx, sy = frame['scroll']
    fade_color, level = frame.get('fade', [0, 0])
    regs = {
        CTRL: 1 | (2 if on else 0),
        BACKDROP: header['backdrop'] & 0xFFFF,
        CLIP_R: (clip1 & 1023) << 16 | (clip0 & 1023),
        WINDOW: (sat12(wy) & 0xFFF) << 16 | (sat12(wx) & 0xFFF),
        SCROLL: (sy & 511) << 16 | (sx & 511),
        FADE: (level & 31) << 16 | (fade_color & 0xFFFF),
        SPRITE_N: len(sprites),
    }
    out += [(REG + 4 * k, v) for k, v in regs.items()]
    return out + [(REG + 4 * COMMIT, 1)]


def soc_script(writes):
    """把总线写压成 C 驱动 (tests/soc/display_check.c) 能重放的脚本 (export --soc 的 script.c)。

    显示的片内 RAM 复位是 0, 所以数据 0 的写和文字层的空白格 (字符 < 33) 可以不重放,
    效果一样; 寄存器区 (偏移 < 0x1000) 不跳 -- 寄存器写 0 有意义 (FADE=0 等)。
    剩下的按原顺序合并成 (地址, 个数, 数据...) 的段, 0xFFFFFFFF 结尾。"""
    kept = []
    for a, d in writes:
        if 0x20000 <= a < 0x30000 and d & 0xFF < 33:
            continue  # 文字层空白格: 复位值 0 也是"不画"
        if d == 0 and a >= 0x1000:
            continue
        kept.append((a, d))
    words, i = [], 0
    while i < len(kept):
        j = i + 1
        while j < len(kept) and kept[j][0] == kept[i][0] + 4 * (j - i):
            j += 1
        words += [kept[i][0], j - i, *(d for _, d in kept[i:j])]
        i = j
    return words + [0xFFFFFFFF]


def lz_pack(data):
    """开机素材的压缩 (板上 gfx_hw.c 的 unpack 解): 字节流, 每段一个头字节
    t < 0x80: 后面 t+1 个原样字节; t >= 0x80: 从 d 字节之前复制 (t & 0x7F) + 3 个 (d 两字节小端, 1..4095, 可以和自己重叠)。
    图案里大片透明 0 和重复的形状, 27 KB 压到 5 KB 左右。贪心最长匹配, 够用。"""
    out, lit, i, heads = bytearray(), bytearray(), 0, {}

    def flush():
        for k in range(0, len(lit), 128):
            chunk = lit[k : k + 128]
            out.append(len(chunk) - 1)
            out.extend(chunk)
        lit.clear()

    while i < len(data):
        best, dist = 0, 0
        for j in reversed(heads.get(bytes(data[i : i + 3]), [])[-64:]):
            if i - j > 4095:
                break
            n = 0
            while n < 130 and i + n < len(data) and data[j + n] == data[i + n]:
                n += 1
            if n > best:
                best, dist = n, i - j
        if best >= 3:
            flush()
            out += bytes([0x80 | (best - 3), dist & 0xFF, dist >> 8])
            step = best
        else:
            lit.append(data[i])
            step = 1
        for k in range(i, i + step):
            heads.setdefault(bytes(data[k : k + 3]), []).append(k)
        i += step
    flush()
    return bytes(out)


def lz_unpack(pack):
    out, i = bytearray(), 0
    while i < len(pack):
        t = pack[i]
        if t < 0x80:
            out += pack[i + 1 : i + 2 + t]
            i += 2 + t
        else:
            d = pack[i + 1] | pack[i + 2] << 8
            for _ in range((t & 0x7F) + 3):
                out.append(out[-d])
            i += 3
    return bytes(out)


def cmd_firmware(args):
    """开机写一次的部分 (同 bus_writes 的前半, 不跳过 0: 板上显示的 RAM 里可能是上一个程序留下的)。
    字库按字节存 (总线上一行占一个字, 直接存要 8 KB), 由板上程序展开。"""
    art = Assets()
    writes = [(PAL + 4 * i, int(c) & 0xFFFF) for i, c in enumerate(art.palette)]
    table, words = image_table(art)
    assert len(words) * 8 <= 57344 and len(table) < 1000, "基础图案侵入立绘保留区"
    writes += [(IMG + 4 * i, code << 13 | base) for i, (code, base) in enumerate(table)]
    for i, w in enumerate(words):
        writes += [(PAT + 8 * i, w & 0xFFFFFFFF), (PAT + 8 * i + 4, w >> 32)]
    script, i = [], 0
    while i < len(writes):
        j = i + 1
        while j < len(writes) and writes[j][0] == writes[i][0] + 4 * (j - i):
            j += 1
        script += [writes[i][0], j - i, *(d for _, d in writes[i:j])]
        i = j
    raw = b''.join(w.to_bytes(4, 'little') for w in script + [0xFFFFFFFF])
    pack = lz_pack(raw)
    assert lz_unpack(pack) == raw
    font = [int(art.font[code][r]) for code in range(128) for r in range(16)]
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        '/* refmodel.py firmware 生成, 不要手改。板上开机写进显示 (见 docs/display.md "每帧怎么用" 第 1 步)。\n'
        f' * {len(table)} 张图案, 图案库 {len(words) * 8} 字节。 */\n'
        '#include <stdint.h>\n\n'
        '/* (偏移, 个数, 数据...) 段, 0xFFFFFFFF 结尾 (偏移相对显示基址), 按小端字节流用 lz_pack 压缩 */\n'
        f'const uint8_t display_pack[{len(pack)}] = {{\n' + assets.c_array(list(pack)) + '\n};\n\n'
        '/* 128 个字 x 16 行, 一行一字节 (最高位在左) */\n'
        'const uint8_t display_font[128 * 16] = {\n' + assets.c_array(font) + '\n};\n'
    )
    print(f'{out}: {len(table)} 张图案, 写 {len(writes)} 次, 素材 {len(raw)} 字节压成 {len(pack)}, 字库 {len(font)}')


def write_hex(path, values, digits):
    Path(path).write_text(''.join(f'{v:0{digits}x}\n' for v in values))


def cmd_export(args):
    art = Assets()
    if args.scene:
        header, frame = make_scenes()[args.scene]
        args.dump = args.scene
    else:
        header, frames = read_dump(args.dump)
        frame = pick(header, frames, art, args.frame)
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    writes = bus_writes(header, frame, art)
    write_hex(out / 'writes.hex', [a << 32 | d for a, d in writes] + [0xFFFFFFFF << 32], 16)
    if args.soc:  # SoC 级测试 (tests/soc/display_tb.sv) 用: CPU 重放的压缩脚本, 见 soc_script
        script = assets.c_array(soc_script(writes), 8)
        (out / 'script.c').write_text(
            f'/* {args.dump} 的总线重放脚本, refmodel.py export --soc 生成, 不要手改。\n'
            ' * display_script[]: (地址, 个数, 数据...) 段, 0xFFFFFFFF 结尾; 零值写和空白文字格已跳过 (片内 RAM 复位为 0)。 */\n'
            '#include <stdint.h>\n\n'
            'const uint32_t display_script[] = {\n' + script + '};\n'
        )
    cam = camera_placeholder()
    write_hex(out / 'window.hex', cam.ravel(), 2)
    rgb = compose(header, frame, art, LINE_OBJECTS)
    write_hex(
        out / 'expect.hex',
        (rgb[..., 0].astype(np.int64) << 16 | rgb[..., 1].astype(np.int64) << 8 | rgb[..., 2]).ravel(),
        6,
    )
    Image.fromarray(rgb).save(out / 'expect.png')
    print(f'{args.dump} 第 {frame["frame"]} 帧: {len(frame["sprites"])} 个精灵, 写 {len(writes)} 次 -> {out}')


def cmd_tables(args):
    sin = '\n'.join(f"            8'd{a}: sin_q14 = {'-' if v < 0 else ''}17'sd{abs(v)};" for a, v in enumerate(SIN))
    inv = '\n'.join(f"            8'd{s}: inv_q12 = 17'd{v};" for s, v in enumerate(INV))
    Path(
        args.output
    ).write_text(f"""// 由 game/tools/refmodel.py tables 生成, 不要手改: 和参考模型的 SIN、INV 是同一份表。
// sin_q14(a): 一圈 256 档, Q14; inv_q12(s): 65536 / s 取整 (s = 16 是原大), inv_q12(0) = 0。
function automatic signed [16:0] sin_q14(input reg [7:0] a);
    begin
        case (a)
{sin}
            default: sin_q14 = 17'sd0;
        endcase
    end
endfunction

function automatic [16:0] inv_q12(input reg [7:0] s);
    begin
        case (s)
{inv}
            default: inv_q12 = 17'd0;
        endcase
    end
endfunction
""")
    print(f'-> {args.output}')


def scene(
    name,
    sprites,
    *,
    window=(0, 0, 0),
    clip=(0, W),
    scroll=(0, 0),
    fade=(0, 0),
    text=None,
    backdrop=0x2104,
    map_fill=None,
):
    """一个场景: 一帧, 格式同 C 的 --dump。"""
    rng = np.random.default_rng(len(name))
    tiles = [i for i, (_, size, _) in enumerate(assets.IMAGES) if size == 8][:8]
    tmap = map_fill if map_fill is not None else [int(rng.choice(tiles)) for _ in range(64 * 64)]
    rows = text or []
    rows = [r.ljust(160)[:160] for r in rows] + [' ' * 160] * (45 - len(rows))
    colors = [''.join('0123456789abcdef'[(r + c) % 16] for c in range(160)) for r in range(45)]
    header = {
        'images': [size for _, size, _ in assets.IMAGES],
        'backdrop': backdrop,
        'clip': list(clip),
        'window': list(window),
        'map': tmap,
    }
    frame = {
        'frame': 0,
        'why': name,
        'scroll': list(scroll),
        'fade': list(fade),
        'sprites': sprites,
        'text': rows,
        'text_color': colors,
    }
    return header, frame


def make_scenes():
    names = [name for name, _, _ in assets.IMAGES]
    img = names.index
    rng = np.random.default_rng(1)
    out = {}
    # 只有背景: 卷动绕回, 游戏区不从 0 开始也不到头; 透明的点露出底色
    out['bg'] = scene('bg', [], clip=(101, 547), scroll=(509, 300))
    # 小窗半出屏 (左下), 文字层所有颜色和不画的字符, 整体混色
    out['window'] = scene(
        'window',
        [[320, 180, img('ring'), ADD, 16, 0, 16]],
        window=(1, -37, 290),
        scroll=(3, 5),
        fade=(0xFFFF, 5),
        text=['ABCdef 0123456789 !@#$%^&*()_+-=[]{};:,./<>?|~`', '\x7f\x01\x1f   x', 'score 1234567'],
    )
    # 不旋转: 各尺寸、四种翻转、三种混合、clip、四边半出屏、同一格连着画 (前递)
    spr = []
    for i in range(160):
        image = int(rng.integers(len(names)))
        flags = (
            int(rng.choice([0, ALPHA, ADD, ADD | ALPHA])) | int(rng.integers(4)) * FLIP_X | int(rng.integers(2)) * CLIP
        )
        spr.append(
            [int(rng.integers(-40, W + 40)), int(rng.integers(-40, H + 40)), image, flags, int(rng.integers(17)), 0, 16]
        )
    for k in range(12):  # 同一个位置连着叠, 每次错开一点
        spr.append([200 + k, 100 + k // 3, img('orb'), ALPHA if k % 2 else ADD, 9, 0, 16])
    for x in (-31, -3, W - 5, W + 3):
        spr.append([x, 50, img('apple'), FLIP_Y, 16, 0, 16])
    for y in (-30, H + 2):
        spr.append([300, y, img('melon'), 0, 16, 0, 16])
    out['sprites'] = scene('sprites', spr, clip=(64, 576))
    # 旋转缩放: 各角度、缩放 (含 0 和很大)、翻转 + 旋转、clip、半出屏
    spr = []
    for i in range(70):
        image = int(rng.integers(len(names)))
        flags = AFFINE | int(rng.choice([0, ALPHA, ADD])) | int(rng.integers(4)) * FLIP_X | int(rng.integers(2)) * CLIP
        spr.append(
            [
                int(rng.integers(-60, W + 60)),
                int(rng.integers(-60, H + 60)),
                image,
                flags,
                int(rng.integers(17)),
                int(rng.integers(256)),
                int(rng.integers(4, 48)),
            ]
        )
    spr += [
        [320, 180, img('ring'), AFFINE | ADD, 16, 0, 76],
        [100, 100, img('melon'), AFFINE, 16, 37, 0],
        [500, 300, img('apple'), AFFINE, 16, 64, 16],
        [5, 5, img('streak'), AFFINE | FLIP_X | FLIP_Y, 16, 200, 255],
    ]
    out['affine'] = scene('affine', spr, clip=(80, 560))
    # 一行超过 128 个对象 (多的丢掉), 表超过 512 个 (多的不画)
    spr = [[int(8 + 4 * (i % 150)), 200 + i // 150, img('bullet'), ADD, 16, 0, 16] for i in range(300)]
    spr += [[int(rng.integers(W)), int(rng.integers(H)), img('spark'), 0, 16, 0, 16] for _ in range(300)]
    out['overflow'] = scene('overflow', spr)
    return out


def cmd_scenes(args):
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    for name, (header, frame) in make_scenes().items():
        (out / f'{name}.jsonl').write_text(json.dumps(header) + '\n' + json.dumps(frame) + '\n')
        print(f'{name}: {len(frame["sprites"])} 个精灵 -> {out / name}.jsonl')


def main():
    parser = argparse.ArgumentParser(usage=__doc__)
    sub = parser.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('render')
    r.add_argument('dump')
    r.add_argument('--frame', type=int)
    r.add_argument('--max-objects', type=int, default=LINE_OBJECTS, help='每行最多几个对象 (0 = 不限; 默认同硬件)')
    r.add_argument('--blade-layer', action='store_true', help='试验: 刀光改成 1280x720 上的平滑线 (刀光层)')
    r.add_argument('-o', '--output')
    c = sub.add_parser('cost')
    c.add_argument('dump', nargs='+')
    c.add_argument('--mhz', type=float, default=50)
    c.add_argument('--setup', type=int, default=4)
    c.add_argument('--affine', type=int, default=1)
    c.add_argument('--bg', type=int, default=80)
    c.add_argument('--rtl', action='store_true', help='按 rtl/display 实际的拍数算 (忽略上面三个参数)')
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
    e = sub.add_parser('export')
    e.add_argument('dump', nargs='?')
    e.add_argument('--frame', type=int)
    e.add_argument('--scene', help='不读存帧, 导出 scenes 里的这个场景')
    e.add_argument('--soc', action='store_true', help='再写一个 script.c: 压缩的总线重放脚本 (tests/soc 的 SoC 级测试用)')
    e.add_argument('-o', '--output', required=True)
    sc = sub.add_parser('scenes')
    sc.add_argument('-o', '--output', required=True)
    fw = sub.add_parser('firmware')
    fw.add_argument('-o', '--output', required=True)
    t = sub.add_parser('tables')
    t.add_argument('-o', '--output', required=True)
    args = parser.parse_args()
    commands = {'render': cmd_render, 'cost': cmd_cost, 'colors': cmd_colors, 'memory': cmd_memory, 'export': cmd_export,
                'scenes': cmd_scenes, 'tables': cmd_tables, 'firmware': cmd_firmware}
    commands[args.cmd](args)


if __name__ == '__main__':
    main()
