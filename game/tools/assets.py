#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""图案和字库 -> C 源文件 (game/build/assets.h, assets.c), 外加一张预览图 assets_preview.png。

用法: game/tools/assets.py <输出目录>     (make 会自动调)

图案: 下面 IMAGES 里每一项, game/assets/<名字>.png 存在就用它 (以后换成生图挑出来的), 否则用程序画的占位图。
按硬件的限制处理:
  - 正方形, 边长 8 / 16 / 32 / 64;
  - 颜色转成 RGB565 (16 位色);
  - 像素只有透明 / 不透明: alpha < 128 算透明, 存成 TRANSPARENT 这个颜色 (洋红)。
    要软边缘、发光的图, 用黑底画, 游戏里用加法混合 (黑色加上去等于没画)。
字库: 8x16, ASCII 32~126, 用系统等宽字体 (Menlo) 画出来再二值化, 只是占位 (授权不能带进比赛作品)。
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent.parent
TRANSPARENT = 0xF81F  # 洋红: 透明; 真的洋红改成 0xF81E


def disk(size, r):
    """每个像素到中心的距离 <= r 的掩码。"""
    c = (size - 1) / 2
    y, x = np.mgrid[:size, :size]
    return np.hypot(x - c, y - c) <= r


def dist(size):
    c = (size - 1) / 2
    y, x = np.mgrid[:size, :size]
    return np.hypot(x - c, y - c)


def paint(size, *layers):
    """从下往上画: 每层 (掩码, 颜色)。返回 RGBA。"""
    img = np.zeros((size, size, 4), np.uint8)
    for mask, color in layers:
        img[mask] = (*color, 255)
    return img


def glow(size, radius, color, ring=None, width=2.5):
    """发光图 (配合加法混合): 中心 (或 ring 那一圈) 最亮, 往外渐暗到黑。"""
    d = dist(size)
    level = np.clip(1 - (d if ring is None else abs(d - ring) / width * radius) / radius, 0, 1) ** 1.5
    img = np.zeros((size, size, 4), np.uint8)
    img[..., :3] = (level[..., None] * color).astype(np.uint8)
    img[..., 3] = np.where(level > 0, 255, 0)
    return img


def tile(star=None, bright=0):
    img = np.zeros((8, 8, 4), np.uint8)
    img[...] = (8, 10, 34, 255)
    if star:
        img[star[1], star[0]] = (bright, bright, bright + 20, 255)
    return img


def player():
    img = np.zeros((16, 16, 4), np.uint8)
    y, x = np.mgrid[:16, :16]
    inside = (y >= 2) & (y <= 14) & (abs(x - 7.5) <= (y - 2) * 0.5)  # 朝上的三角
    img[inside] = (110, 200, 90, 255)
    return img


def rice():
    """米弹: 朝右 (角度 0) 的椭圆, 游戏里按飞行方向旋转。"""
    y, x = np.mgrid[:16, :16] - 7.5
    outer = (x / 7.5) ** 2 + (y / 3.5) ** 2 <= 1
    inner = (x / 5) ** 2 + (y / 1.8) ** 2 <= 1
    return paint(16, (outer, (60, 220, 120)), (inner, (230, 255, 235)))


def shot():
    img = np.zeros((16, 16, 4), np.uint8)
    img[2:14, 7:9] = (150, 230, 255, 255)
    return img


def wood(dark, knot=None):
    """水果忍者的背景: 木板。8x8 一块, 上下拼成竖纹; dark 那一列是木板之间的缝。"""
    img = np.zeros((8, 8, 4), np.uint8)
    img[...] = (96, 62, 36, 255)
    img[:, 3] = (106, 70, 42, 255)
    if dark is not None:
        img[:, dark] = (48, 30, 18, 255)
    if knot:
        img[knot[1] : knot[1] + 2, knot[0] : knot[0] + 2] = (70, 44, 26, 255)
    return img


def fruit(size, peel, flesh, leaf=None):
    """整个水果: 外皮一圈, 里面稍亮 (有点立体感), 左上一点高光。"""
    r = size / 2 - 1
    c = (size - 1) / 2
    y, x = np.mgrid[:size, :size]
    layers = [(disk(size, r), peel), (disk(size, r * 0.8), tuple(min(255, v + 25) for v in peel)),
              ((x - (c - r * 0.35)) ** 2 + (y - (c - r * 0.35)) ** 2 <= (r * 0.18) ** 2, (255, 255, 240))]
    if leaf:
        layers.append(((abs(x - c - 2) <= 2) & (y <= 3), leaf))
    return paint(size, *layers)


def half(size, peel, flesh, seed):
    """切开的左半边: 刀口是竖直的那条边 (游戏里按刀的方向转, 另一半左右翻转)。"""
    r = size / 2 - 1
    c = (size - 1) / 2
    y, x = np.mgrid[:size, :size]
    left = x <= c
    layers = [(disk(size, r) & left, peel), (disk(size, r - max(2, size // 16)) & left, flesh),
              (disk(size, r * 0.3) & left & ((x + y) % 3 == 0), seed)]
    return paint(size, *layers)


def streak():
    """刀光的一笔 (配合加法、旋转): 横着的一道, 中间 2 点最亮, 上下各约 4 点淡出;
    两头 4 点线性变暗, 游戏里每隔 12 点放一笔, 相邻两笔两头叠起来亮度正好接上。"""
    y, x = np.mgrid[:16, :16] + 0.5
    across = np.clip(1 - np.maximum(abs(y - 8) - 1, 0) / 4, 0, 1) ** 1.5
    along = np.clip(np.minimum(x, 16 - x) / 4, 0, 1)
    level = across * along
    img = np.zeros((16, 16, 4), np.uint8)
    img[..., :3] = (level[..., None] * np.array([210, 240, 255])).astype(np.uint8)
    img[..., 3] = np.where(level > 0, 255, 0)
    return img


def blob(size, color, seed):
    """不规则的一团果汁 (不透明, 游戏里整体半透明淡出): 几个圆叠起来。"""
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[:size, :size]
    mask = np.zeros((size, size), bool)
    c = (size - 1) / 2
    mask |= np.hypot(x - c, y - c) <= size * 0.28
    for _ in range(6):
        a, d = rng.uniform(0, 2 * np.pi), rng.uniform(0.15, 0.32) * size
        r = rng.uniform(0.07, 0.16) * size
        mask |= np.hypot(x - c - d * np.cos(a), y - c - d * np.sin(a)) <= r
    img = np.zeros((size, size, 4), np.uint8)
    img[mask] = (*color, 255)
    hi = np.hypot(x - c + size * 0.1, y - c + size * 0.1) <= size * 0.08
    img[mask & hi] = (*[min(255, v + 70) for v in color], 255)
    return img


def bomb():
    img = paint(32, (disk(32, 12), (40, 40, 48)), (disk(32, 9), (60, 60, 72)))
    y, x = np.mgrid[:32, :32]
    img[((x - 11) ** 2 + (y - 11) ** 2 <= 5)] = (170, 170, 190, 255)  # 高光
    img[1:6, 15:17] = (150, 120, 80, 255)  # 引信
    return img


# 名字, 边长, 占位图。顺序就是编号 (IMG_*), 背景图块要在前面 (硬件里图块编号可能位数少)
IMAGES = [
    ('tile0', 8, lambda: tile()),
    ('tile1', 8, lambda: tile((2, 3), 120)),
    ('tile2', 8, lambda: tile((5, 6), 200)),
    ('tile3', 8, lambda: tile((6, 1), 80)),
    ('wood0', 8, lambda: wood(None)),
    ('wood1', 8, lambda: wood(7)),
    ('wood2', 8, lambda: wood(None, (4, 2))),
    ('wood3', 8, lambda: wood(7, (1, 5))),
    ('bullet', 8, lambda: paint(8, (disk(8, 3.6), (230, 50, 60)), (disk(8, 1.6), (255, 230, 230)))),
    ('orb', 16, lambda: paint(16, (disk(16, 7.4), (60, 90, 240)), (disk(16, 4.5), (150, 190, 255)), (disk(16, 2), (255, 255, 255)))),
    ('rice', 16, rice),
    ('player', 16, player),
    ('hitbox', 8, lambda: paint(8, (disk(8, 3.6), (230, 40, 40)), (disk(8, 2.2), (255, 255, 255)))),
    ('shot', 16, shot),
    ('spark', 8, lambda: glow(8, 4, np.array([255, 220, 120]))),
    ('boss', 32, lambda: paint(32, (disk(32, 15), (170, 50, 170)), (disk(32, 11), (230, 110, 220)), (disk(32, 5), (255, 230, 250)))),
    ('ring', 64, lambda: glow(64, 31, np.array([120, 200, 255]), ring=28, width=4)),
    # 水果忍者
    ('apple', 32, lambda: fruit(32, (200, 30, 40), None, (60, 160, 50))),
    ('apple_half', 32, lambda: half(32, (200, 30, 40), (250, 235, 190), (90, 50, 20))),
    ('orange', 32, lambda: fruit(32, (240, 140, 20), None)),
    ('orange_half', 32, lambda: half(32, (240, 140, 20), (255, 200, 80), (255, 240, 200))),
    ('melon', 64, lambda: fruit(64, (40, 120, 40), None)),
    ('melon_half', 64, lambda: half(64, (40, 120, 40), (235, 60, 70), (30, 20, 20))),
    ('bomb', 32, bomb),
    ('juice_red', 8, lambda: glow(8, 4, np.array([255, 60, 60]))),
    ('juice_orange', 8, lambda: glow(8, 4, np.array([255, 170, 40]))),
    ('juice_green', 8, lambda: glow(8, 4, np.array([120, 255, 90]))),
    ('blade', 8, lambda: glow(8, 4, np.array([200, 240, 255]))),
    ('streak', 16, streak),
    ('drop_red', 16, lambda: blob(16, (200, 20, 40), 1)),
    ('drop_orange', 16, lambda: blob(16, (240, 150, 20), 2)),
    ('drop_cream', 16, lambda: blob(16, (240, 225, 160), 3)),
    ('stain_red', 32, lambda: blob(32, (150, 20, 35), 4)),
    ('stain_orange', 32, lambda: blob(32, (190, 110, 20), 5)),
    ('stain_cream', 32, lambda: blob(32, (190, 170, 110), 6)),
]


def load(name, size, make):
    path = HERE / 'assets' / f'{name}.png'
    if not path.exists():
        return make()
    img = np.asarray(Image.open(path).convert('RGBA'))
    if img.shape[:2] != (size, size):
        sys.exit(f'{path}: 要 {size}x{size}, 实际 {img.shape[1]}x{img.shape[0]}')
    return img


def rgb565(img):
    """RGBA -> RGB565, 透明的点换成 TRANSPARENT。"""
    r, g, b = (img[..., i].astype(np.uint16) for i in range(3))
    out = (r >> 3) << 11 | (g >> 2) << 5 | (b >> 3)
    out[out == TRANSPARENT] = TRANSPARENT - 1
    out[img[..., 3] < 128] = TRANSPARENT
    return out


def font():
    """8x16 字库: 每个字 16 个字节 (一行一字节, 最高位在左)。"""
    face = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 13)
    glyphs = np.zeros((128, 16), np.uint8)
    for code in range(32, 127):
        img = Image.new('L', (8, 16))
        ImageDraw.Draw(img).text((0, 0), chr(code), fill=255, font=face)
        bits = np.asarray(img) >= 110
        glyphs[code] = np.packbits(bits, axis=1)[:, 0]
    return glyphs


def c_array(values, per_line=16):
    rows = [', '.join(f'0x{v:04X}' if v > 255 else f'0x{v:02X}' for v in values[i : i + per_line]) for i in range(0, len(values), per_line)]
    return '\n'.join(f'    {r},' for r in rows)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    images = [(name, size, rgb565(load(name, size, make))) for name, size, make in IMAGES]

    ids = '\n'.join(f'    IMG_{name.upper()},' for name, _, _ in images)
    (out / 'assets.h').write_text(f"""/* 由 game/tools/assets.py 生成, 不要手改 */
#ifndef ASSETS_H
#define ASSETS_H

#include <stdint.h>

#define ASSET_TRANSPARENT 0x{TRANSPARENT:04X} /* 透明点的颜色 */

enum {{
{ids}
    IMG_COUNT,
}};

typedef struct {{
    uint8_t size;           /* 边长 */
    const uint16_t *pixels; /* size x size 个 RGB565, 逐行 */
}} asset_image_t;

extern const asset_image_t assets_images[IMG_COUNT];
extern const uint8_t assets_font[128][16]; /* 8x16, 一行一字节, 最高位在左 */

#endif
""")

    parts = ['/* 由 game/tools/assets.py 生成, 不要手改 */', '#include "assets.h"', '']
    for name, size, pixels in images:
        parts.append(f'static const uint16_t {name}[{size * size}] = {{\n{c_array(pixels.ravel().tolist())}\n}};\n')
    table = '\n'.join(f'    {{{size}, {name}}},' for name, size, _ in images)
    parts.append(f'const asset_image_t assets_images[IMG_COUNT] = {{\n{table}\n}};\n')
    glyphs = font()
    rows = '\n'.join(f'    {{{", ".join(f"0x{v:02X}" for v in g)}}},' for g in glyphs.tolist())
    parts.append(f'const uint8_t assets_font[128][16] = {{\n{rows}\n}};\n')
    (out / 'assets.c').write_text('\n'.join(parts))

    # 预览: 每个图案放大 4 倍排成一行, 透明处画成灰格; 下面是字库
    scale, pad = 4, 8
    width = sum(s * scale + pad for _, s, _ in images) + pad
    sheet = Image.new('RGB', (max(width, 96 * 8 * 2 + 2 * pad), 64 * scale + 2 * pad + 6 * 16 * 2 + pad), (60, 60, 60))
    x = pad
    for _, size, pixels in images:
        rgb = np.stack([(pixels >> 11) << 3, ((pixels >> 5) & 63) << 2, (pixels & 31) << 3], -1).astype(np.uint8)
        rgb[pixels == TRANSPARENT] = (90, 90, 90)
        sheet.paste(Image.fromarray(rgb).resize((size * scale, size * scale), Image.Resampling.NEAREST), (x, pad))
        x += size * scale + pad
    bits = np.unpackbits(glyphs[32:128].reshape(6, 16, 16)[..., None], axis=-1)  # 6 排, 每排 16 个字, 每字 16 行 x 8 点
    text = bits.transpose(0, 2, 1, 3).reshape(6 * 16, 16 * 8) * 255
    sheet.paste(Image.fromarray(text.astype(np.uint8)).resize((16 * 8 * 2, 6 * 16 * 2), Image.Resampling.NEAREST), (pad, 64 * scale + 2 * pad))
    sheet.save(out / 'assets_preview.png')
    print(f'{len(images)} 个图案, 字库 95 个字 -> {out}')


if __name__ == '__main__':
    main()
