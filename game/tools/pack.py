#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""用户素材 -> AMA.PAK; 不需要联网素材。格式见 docs/sd.md。"""

import argparse
import json
import math
import struct
import subprocess
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageOps

import assets
from refmodel import palettize

ROOT = Path(__file__).resolve().parent.parent
MAGIC = b'AMAPAK1\0'
PORTRAIT, BGM = 1, 2


def align(n):
    return (n + 511) & ~511


def portrait(path):
    # 保持比例, 透明补边。半分辨率 64x96, 三个方块, 硬件 scale=32 显示128x192。
    src = Image.open(path).convert('RGBA')
    src = ImageOps.contain(src, (64, 96), Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (64, 96))
    canvas.alpha_composite(src, ((64 - src.width) // 2, 96 - src.height))
    image = assets.rgb565(np.asarray(canvas)).astype(np.int32)
    if np.all(image == assets.TRANSPARENT):
        pal, indices = np.zeros(256, dtype=np.int32), [np.zeros((96, 64), dtype=np.int32)]
    else:
        pal, indices = palettize([image], 128)
    index = indices[0]
    index = np.where(index == 0, 0, index + 127).astype(np.uint8)
    # palettize 返回 1..128; PAK 使用 128..255, 0 仍透明。
    palette = pal[1:129].astype('<u2').tobytes().ljust(512, b'\0')
    return palette + index[:64].tobytes() + index[64:, :32].tobytes() + index[64:, 32:].tobytes()


def pcm(path):
    try:
        result = subprocess.run(
            ['ffmpeg', '-v', 'error', '-i', str(path), '-f', 's8', '-ar', '16000', '-ac', '1', '-'],
            check=True,
            capture_output=True,
        ).stdout
    except FileNotFoundError as e:
        raise SystemExit('需要 ffmpeg (wav/ogg/mp3 -> 16 kHz 单声道 signed PCM8)') from e
    if not result:
        raise ValueError(f'空音频: {path}')
    return result.ljust((len(result) + 3) & ~3, b'\0')


def demo(root):
    """只生成原创几何人像和四音合成旋律; 不覆盖已有素材。"""
    p, b = root / 'portraits', root / 'bgm'
    p.mkdir(parents=True, exist_ok=True)
    b.mkdir(parents=True, exist_ok=True)
    out = p / 'demo.png'
    if not out.exists():
        im = Image.new('RGBA', (128, 192))
        d = ImageDraw.Draw(im)
        d.polygon([(64, 70), (12, 188), (116, 188)], fill=(45, 110, 210))
        d.ellipse((34, 10, 94, 78), fill=(240, 190, 140))
        d.polygon([(28, 34), (64, 0), (100, 34)], fill=(75, 40, 110))
        d.rectangle((48, 40, 52, 45), fill=(15, 20, 35))
        d.rectangle((76, 40, 80, 45), fill=(15, 20, 35))
        im.save(out)
    out = b / 'demo.wav'
    if not out.exists():
        values = []
        notes = (261.63, 329.63, 392, 523.25)
        for n in range(32000):
            phase = n % 8000
            env = min(1, phase / 160, (7999 - phase) / 320)
            values.append(int(7000 * env * math.sin(2 * math.pi * notes[n // 8000] * n / 16000)))
        with wave.open(str(out), 'wb') as f:
            f.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
            f.writeframes(struct.pack(f'<{len(values)}h', *values))


def pack(root, output):
    items = []
    manifest = []
    for kind, folder, suffixes in ((PORTRAIT, 'portraits', {'.png'}), (BGM, 'bgm', {'.wav', '.ogg', '.mp3'})):
        paths = sorted(p for p in (root / folder).glob('*') if p.suffix.lower() in suffixes)
        seen = set()
        for id_, path in enumerate(paths):
            name = path.stem.encode('ascii')
            if not name or len(name) > 23 or name in seen:
                raise ValueError(f'名字须为唯一 ASCII, 最多23字节: {path}')
            seen.add(name)
            data = portrait(path) if kind == PORTRAIT else pcm(path)
            loop_start = loop_end = 0
            sidecar = path.with_suffix('.loop.json')
            if kind == BGM and sidecar.exists():
                loop = json.loads(sidecar.read_text())
                loop_start, loop_end = loop['start'], loop['end']
                if not (0 <= loop_start < loop_end <= len(data)) or (loop_start | loop_end) & 3:
                    raise ValueError(f'循环点须为4对齐样本数且在文件内: {sidecar}')
            items.append((name, kind, id_, data, loop_start, loop_end))
            manifest.append(
                dict(name=path.stem, type=kind, id=id_, length=len(data), loop_start=loop_start, loop_end=loop_end)
            )
    if len(items) > 64:
        raise ValueError('最多64个素材')
    offset = align(512 + 64 * len(items))
    directory, payload = bytearray(), bytearray()
    for item, info in zip(items, manifest):
        name, kind, id_, data, start, end = item
        directory += struct.pack('<24s6I16x', name, kind, id_, offset, len(data), start, end)
        info['offset'] = offset
        payload += data.ljust(align(len(data)), b'\0')
        offset += align(len(data))
    header = struct.pack('<8s3I', MAGIC, 1, len(items), offset).ljust(512, b'\0')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(header + directory.ljust(align(len(directory)), b'\0') + payload)
    output.with_suffix('.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'{output}: {len(items)} 个素材, {offset} bytes (编号见 {output.with_suffix(".json")})')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', type=Path, default=ROOT / 'assets')
    parser.add_argument('-o', '--output', type=Path, default=ROOT / 'build/AMA.PAK')
    parser.add_argument('--demo', action='store_true')
    args = parser.parse_args()
    if args.demo:
        demo(args.assets)
    pack(args.assets, args.output)


if __name__ == '__main__':
    main()
