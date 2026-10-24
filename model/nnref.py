#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""handnet 的 int8 定点参考实现 —— rtl/nn/ 的标准答案。

网络结构和 model/handnet.py 一样 (宽度可调), 但这里算的是硬件真正做的整数运算:

    acc = Σ q_in * w_q                          (int32 累加)
    y   = ((acc * M) + (1 << (SH-1))) >> SH + Z (M 每输出通道一个 int32, SH/Z 每层一个)
    y   = clamp(y, Z if relu else -128, 127)

越界 (卷积 padding) 的输入取 pad_q, 它的意思就是"该层输入量化里的实数 0"。

权重/偏置/乘数由 model/nn_export.py 量化后给出, 本文件只负责"同样的数字, 同样的结果"。
tests/nn/nn_tb.sv 拿它的输出和 RTL 逐字节比较; 改 RTL 后先跑这个。

用法:
    model/nnref.py                        # 用导出时存下的模型自检 (和 RTL 的测试向量比)
    model/nnref.py --demo                 # 算 sw/app/nn_demo 那张合成图的校验和, 和串口打印的对
    model/nnref.py <layers.npz> <in.raw>  # 自己指定模型和输入
"""

import sys

import numpy as np

LANES = 16  # 一个 128 位字里的通道数, 和 RTL 的并行度一致
INT8_MIN, INT8_MAX = -128, 127


def requant(acc, m, sh, z, relu):
    """acc: int64 数组; m: 每个输出通道的 int32 乘数; sh/z: 每层一个。

    和 RTL 一致: 先加半个 LSB 再算术右移 (负数右移在 Python 和 Verilog 的 >>> 都是向下取整)。
    """
    p = acc * m
    if sh > 0:
        p = (p + (1 << (sh - 1))) >> sh
    y = p + z
    lo = z if relu else INT8_MIN
    return np.clip(y, lo, INT8_MAX).astype(np.int8)


def pad_input(x, pad, value):
    """在空间维度上补 value (int8), 通道不变。"""
    if pad == 0:
        return x
    h, w, c = x.shape
    out = np.full((h + 2 * pad, w + 2 * pad, c), value, dtype=np.int8)
    out[pad : pad + h, pad : pad + w] = x
    return out


def run_layer(layer, x):
    """一层卷积 (dense 或 depthwise), x: (in_h, in_w, cin) int8 -> (out_h, out_w, cout) int8。

    cout 向上取整到 16 的倍数, 多出来的通道写 0 (和 RTL 的整字写一致)。
    """
    k, stride = layer['k'], layer['stride']
    pad = 1 if k == 3 else 0
    cin, cout = layer['cin'], layer['cout']
    out_h, out_w = layer['out_h'], layer['out_w']
    xp = pad_input(x, pad, layer['pad_q'])
    cgroups = (cout + LANES - 1) // LANES
    padded_cout = cgroups * LANES

    acc = np.zeros((out_h, out_w, padded_cout), dtype=np.int64)
    w = layer['w']  # (padded cout, cin//groups, k, k) int8
    for ky in range(k):
        for kx in range(k):
            if layer['mode'] == 'dw':
                # 每个通道各卷各的: 一个抽头就是 16 条通道各一个乘加
                src = xp[ky : ky + stride * (out_h - 1) + 1 : stride, kx : kx + stride * (out_w - 1) + 1 : stride]
                acc += src.astype(np.int64) * w[:, 0, ky, kx].astype(np.int64)[None, None, :]
            else:
                for ic in range(cin):
                    src = xp[
                        ky : ky + stride * (out_h - 1) + 1 : stride,
                        kx : kx + stride * (out_w - 1) + 1 : stride,
                        ic,
                    ].astype(np.int64)
                    acc += src[:, :, None] * w[:, ic, ky, kx].astype(np.int64)[None, None, :]

    acc += layer['b'].astype(np.int64)[None, None, :]
    y = requant(acc, layer['m'].astype(np.int64), layer['sh'], layer['zout'], layer['relu'])
    y[:, :, cout:] = 0  # 补出来的通道写 0
    return y


def input_quantize(img_rgb):
    """RGB888 (h,w,3) uint8 -> (h,w,4) int8, 通道顺序 BGR (和 model/handnet.py 一致)。

    handnet 的输入是 pixel/255 - 0.5, 量化成 s = 1/255, Z = 0 的 int8:
    q = pixel - 128 (= pixel ^ 0x80)。第 4 个字节是硬件 32 位字的填充, 恒为 0。
    """
    h, w = img_rgb.shape[:2]
    q = (np.ascontiguousarray(img_rgb[:, :, ::-1]).astype(np.uint8) ^ 0x80).view(np.int8)  # RGB -> BGR
    out = np.zeros((h, w, 4), dtype=np.int8)
    out[:, :, :3] = q
    return out


def run(model, img_rgb):
    """整网推理。img_rgb: (120,160,3) uint8 -> 输出字 (out_h*out_w, 16) int8。"""
    x = input_quantize(img_rgb)
    for layer in model['layers']:
        x = run_layer(layer, x)
    return x.reshape(-1, x.shape[-1])


def checksum(out_words):
    """和 C 侧 nn_checksum() 一致的 32 位滚动校验 (FNV-1a, 只算每个字的前 4 个通道)。"""
    h = 2166136261
    for word in np.asarray(out_words).reshape(-1, 16):
        for b in word[:4]:
            h = ((h ^ int(np.uint8(b))) * 16777619) & 0xFFFFFFFF
    return h


def demo_frame():
    """和 sw/app/nn_demo/main.c 的 load_frame() 一模一样的图: 深色背景上一个亮块。"""
    img = np.full((120, 160, 3), (20, 22, 26), dtype=np.uint8)
    img[30:90, 50:120] = (208, 162, 141)
    return img


def load(path):
    """读 nn_export.py 存下的模型 (npz), 返回 dict。"""
    z = np.load(path, allow_pickle=True)
    meta = z['meta'].item()
    layers = []
    for i in range(meta['n_layers']):
        d = dict(meta['layers'][i])
        for key in ('w', 'b', 'm'):
            d[key] = z[f'{key}{i}']
        layers.append(d)
    return dict(meta, layers=layers)


def main(argv):
    if len(argv) > 1 and argv[1] == '--demo':
        from pathlib import Path

        root = Path(__file__).resolve().parent.parent
        model = load(root / 'tests/nn/model.npz')
        out = run(model, demo_frame())
        print(f'nn_demo 那张图的校验和 0x{checksum(out):08x}')
        return

    if len(argv) < 2:
        # 自检: 用 tests/nn 里的测试向量跑一遍, 打印校验和 + 前 4 个字
        from pathlib import Path

        root = Path(__file__).resolve().parent.parent
        model = load(root / 'tests/nn/model.npz')
        raw = np.fromfile(root / 'tests/nn/in.raw', dtype=np.uint8).reshape(120, 160, 3)
        out = run(model, raw)
        exp = np.fromfile(root / 'tests/nn/expect.raw', dtype=np.int8).reshape(-1, 16)
        same = np.array_equal(out, exp)
        print(f'参考实现自检: {"一致" if same else "不一致"}  校验和 0x{checksum(out):08x}')
        if not same:
            bad = np.argwhere(out != exp)[:8]
            print('前几处不同 (字, 通道):', bad.tolist())
            sys.exit(1)
        return

    model = load(argv[1])
    h, w = model['in_h'], model['in_w']
    raw = np.fromfile(argv[2], dtype=np.uint8).reshape(h, w, 3)
    out = run(model, raw)
    print(f'校验和 0x{checksum(out):08x}')


if __name__ == '__main__':
    main(sys.argv)
