#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""把 handnet 量化成 rtl/nn/ 用的权重、层表和测试向量。

产出 (全部是生成文件, 不要手改):
    rtl/nn/nn_model.vh      网络尺寸、各缓冲和 ROM 的深度
    rtl/nn/nn_layers.v      层表 (纯组合常量)
    rtl/nn/nn_w.mem         权重 128 位字 (一拍 16 个输出通道)
    rtl/nn/nn_bm.mem        每输出通道 {int32 定点乘数, int32 偏置}
    sw/nn/nn_tables.h       后处理用的 sigmoid 表和小工具常量
    tests/nn/in.raw         测试输入 (120x160 RGB888)
    tests/nn/expect.raw     标准答案 (300 字 x 16 字节)
    tests/nn/model.npz      量化后的模型, model/nnref.py 读它

用法:
    model/nn_export.py                        # 固定种子的随机权重 (没有 .pt 时也能验证 RTL); --dw-k 3 导出旧结构
    model/nn_export.py model/runs/x.pt        # 从 model/train.py 存的权重导出 (需要 torch)
    model/nn_export.py --calib frames.raw     # 用真实画面标定 (每帧 120*160*3 字节, 可多帧)
    model/nn_export.py model/runs/x.pt --calib model/data   # 标定直接用录的数据 (train.py 缓存的 small_160.npy)

量化 (PTQ: 每通道对称权重, 每张量非对称激活):
    q_in  = round(real/s_in) + Z_in
    acc   = Σ q_in*w_q + (bias/(s_in*s_w) - Z_in*Σw_q)
    q_out = clamp((acc*M) >> SH + Z_out),  M = s_in*s_w/s_out (int32), SH 每层一个
ReLU 层的下限取 Z_out (等价于实数域 max(0, x))。
"""

import argparse
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

LANES = 16  # 一个 128 位字里的通道数, 和 RTL 的并行度一致


def spec(width, dw_k=3, in_w=160, in_h=120):
    """handnet 的层表 (和 model/handnet.py 的 body/head 逐层对应); dw_k: 不缩小的两块 (dw3、dw4) 的深度卷积核。"""
    layers = [
        {'name': 'conv0', 'mode': 'conv', 'k': 3, 'stride': 2, 'cin': 3, 'cout': width, 'relu': True},
        {'name': 'dw1', 'mode': 'dw', 'k': 3, 'stride': 2, 'cin': width, 'cout': width, 'relu': True},
        {'name': 'pw1', 'mode': 'conv', 'k': 1, 'stride': 1, 'cin': width, 'cout': 2 * width, 'relu': True},
        {'name': 'dw2', 'mode': 'dw', 'k': 3, 'stride': 2, 'cin': 2 * width, 'cout': 2 * width, 'relu': True},
        {'name': 'pw2', 'mode': 'conv', 'k': 1, 'stride': 1, 'cin': 2 * width, 'cout': 4 * width, 'relu': True},
        {'name': 'dw3', 'mode': 'dw', 'k': dw_k, 'stride': 1, 'cin': 4 * width, 'cout': 4 * width, 'relu': True},
        {'name': 'pw3', 'mode': 'conv', 'k': 1, 'stride': 1, 'cin': 4 * width, 'cout': 4 * width, 'relu': True},
        {'name': 'dw4', 'mode': 'dw', 'k': dw_k, 'stride': 1, 'cin': 4 * width, 'cout': 4 * width, 'relu': True},
        {'name': 'pw4', 'mode': 'conv', 'k': 1, 'stride': 1, 'cin': 4 * width, 'cout': 4 * width, 'relu': True},
        {'name': 'head', 'mode': 'conv', 'k': 1, 'stride': 1, 'cin': 4 * width, 'cout': 4, 'relu': False},
    ]
    w, h = in_w, in_h
    for la in layers:
        la['in_w'], la['in_h'] = w, h
        w, h = w // la['stride'], h // la['stride']
        la['out_w'], la['out_h'] = w, h
        la['groups'] = la['cin'] if la['mode'] == 'dw' else 1
    return layers


def make_weights(layers, ckpt, seed=1):
    """每层的 (w float32 (cout, cin/groups, k, k), b float32 (cout,)); BN 折进卷积。"""
    if ckpt:
        import torch

        sd = torch.load(ckpt, map_location='cpu')['state']

        def fold(prefix):
            w = sd[prefix + '.0.weight'].numpy().astype(np.float32)  # conv, bias=False
            g = sd[prefix + '.1.weight'].numpy().astype(np.float32)
            be = sd[prefix + '.1.bias'].numpy().astype(np.float32)
            mu = sd[prefix + '.1.running_mean'].numpy().astype(np.float32)
            var = sd[prefix + '.1.running_var'].numpy().astype(np.float32)
            sc = g / np.sqrt(var + 1e-5)
            return w * sc[:, None, None, None], be - mu * sc

        ws, body = [], 0
        for la in layers:
            if la['name'] == 'head':
                ws.append((sd['head.weight'].numpy().astype(np.float32),
                           sd['head.bias'].numpy().astype(np.float32)))
            elif la['name'] == 'conv0':
                ws.append(fold('body.0'))
                body = 1
            elif la['mode'] == 'dw':
                ws.append(fold(f'body.{body}.0'))
            else:
                ws.append(fold(f'body.{body}.1'))
                body += 1
        return ws

    rng = np.random.default_rng(seed)
    ws = []
    for la in layers:
        fan_in = (la['cin'] // la['groups']) * la['k'] * la['k']
        w = rng.normal(0.0, np.sqrt(2.0 / fan_in), (la['cout'], la['cin'] // la['groups'], la['k'], la['k']))
        b = rng.normal(0.0, 0.05, la['cout'])
        ws.append((w.astype(np.float32), b.astype(np.float32)))
    return ws


def calib_images(n, seed=7):
    """标定用的"像画面"的图: 深色背景 + 亮块, 而不是纯噪声。

    真实模型用 --calib 指定录下来的画面 (model/data 里的 160x120 原图)。
    """
    rng = np.random.default_rng(seed)
    out = []
    for _ in range(n):
        img = rng.integers(0, 40, (120, 160, 3), dtype=np.uint8)
        for _ in range(int(rng.integers(1, 3))):
            y, x = int(rng.integers(0, 100)), int(rng.integers(0, 140))
            h, w = int(rng.integers(20, 60)), int(rng.integers(20, 60))
            img[y : y + h, x : x + w] = rng.integers(60, 256, 3)
        out.append(img)
    return out


def forward_float(layers, ws, img):
    """float 前向, 返回每层 (ReLU 之后) 的输出, 用来标定范围。"""
    x = img.astype(np.float32) / 255.0 - 0.5
    x = x[:, :, ::-1]  # RGB -> BGR, 和 model/handnet.py 一致
    outs = []
    for la, (w, b) in zip(layers, ws):
        k, s, pad = la['k'], la['stride'], la['k'] // 2
        xp = np.pad(x, ((pad, pad), (pad, pad), (0, 0)))
        oh, ow = la['out_h'], la['out_w']
        acc = np.zeros((oh, ow, la['cout']), dtype=np.float32)
        for ky in range(k):
            for kx in range(k):
                sl = xp[ky : ky + s * (oh - 1) + 1 : s, kx : kx + s * (ow - 1) + 1 : s]
                if la['mode'] == 'dw':
                    acc += sl * w[:, 0, ky, kx][None, None, :]
                else:
                    for ic in range(la['cin']):
                        acc += sl[:, :, ic][:, :, None] * w[:, ic, ky, kx][None, None, :]
        acc += b[None, None, :]
        x = np.maximum(acc, 0.0) if la['relu'] else acc
        outs.append(x)
    return outs


def quantize(layers, ws, ranges):
    """float 模型 -> 整数模型。s_in/z_in 从输入开始逐层往下传。"""
    s_in, z_in = 1.0 / 255.0, 0  # 输入: pixel/255 - 0.5, s = 1/255, Z = 0
    qlayers = []
    for la, (w, b), (amin, amax) in zip(layers, ws, ranges):
        cout, cin_g, k, _ = w.shape
        cgroups = (cout + LANES - 1) // LANES
        padded = cgroups * LANES

        wmax = np.abs(w).reshape(cout, -1).max(axis=1)
        s_w = np.where(wmax > 0, wmax / 127.0, 1.0)
        wq = np.zeros((padded, cin_g, k, k), dtype=np.int8)
        wq[:cout] = np.clip(np.round(w / s_w[:, None, None, None]), -127, 127).astype(np.int8)
        wsum = wq[:cout].reshape(cout, -1).sum(axis=1).astype(np.int64)

        lo, hi = float(min(0.0, amin)), float(max(0.0, amax))
        if hi - lo < 1e-6:
            hi = lo + 1e-6
        s_out = (hi - lo) / 255.0
        z_out = int(np.clip(np.round(-lo / s_out) - 128, -128, 127))

        bias_q = np.round(b / (s_in * s_w)).astype(np.int64) - z_in * wsum
        bias_q = np.clip(bias_q, -(2**31), 2**31 - 1)

        m_real = s_in * s_w / s_out
        top = float(m_real.max())
        sh = int(max(0, 30 - np.floor(np.log2(top)))) if top > 0 else 0
        m_int = np.round(m_real * (2.0**sh)).astype(np.int64)
        while sh > 0 and m_int.min() == 0:  # 乘数被截成 0 的通道: 退一点, 保精度
            sh -= 1
            m_int = np.round(m_real * (2.0**sh)).astype(np.int64)
        m_int = np.clip(m_int, -(2**31), 2**31 - 1)

        bq = np.zeros(padded, dtype=np.int32)
        mq = np.zeros(padded, dtype=np.int32)
        bq[:cout] = bias_q.astype(np.int32)
        mq[:cout] = m_int.astype(np.int32)

        qlayers.append(dict(la, w=wq, b=bq, m=mq, s_out=s_out, sh=sh, zout=z_out, pad_q=z_in))
        s_in, z_in = s_out, z_out
    return qlayers


def pack_roms(layers):
    """权重按 [tap][通道组][16 通道] 排; 乘数/偏置按输出通道排。"""
    w_words, bm_words = [], []
    w_base = bm_base = 0
    for la in layers:
        k, cin = la['k'], la['cin']
        cgroups = (la['cout'] + LANES - 1) // LANES
        taps = (cin // la['groups']) * k * k
        la['w_base'], la['bm_base'] = w_base, bm_base
        for t in range(taps):
            for cg in range(cgroups):
                if la['mode'] == 'dw':
                    sl = la['w'][cg * LANES : (cg + 1) * LANES, 0, t // k, t % k]
                else:
                    ic, kk = divmod(t, k * k)
                    sl = la['w'][cg * LANES : (cg + 1) * LANES, ic, kk // k, kk % k]
                w_words.append(int.from_bytes(np.asarray(sl, dtype=np.uint8).tobytes(), 'little'))
        for c in range(cgroups * LANES):
            bm_words.append(int.from_bytes(
                struct.pack('<II', int(la['m'][c]) & 0xFFFFFFFF, int(la['b'][c]) & 0xFFFFFFFF), 'little'))
        w_base += taps * cgroups
        bm_base += cgroups * LANES
    return w_words, bm_words


def buffer_words(layers):
    """A/B 两个特征缓冲各自要多少个 128 位字。"""
    a = b = 0
    for i, la in enumerate(layers):
        la['dst_b'] = (i % 2) == 1
        la['src_in'] = i == 0
        words = la['out_w'] * la['out_h'] * ((la['cout'] + LANES - 1) // LANES)
        if la['dst_b']:
            b = max(b, words)
        else:
            a = max(a, words)
    return a, b


def pow2(n):
    p = 1
    while p < n:
        p *= 2
    return p


def emit_layers_v(layers, path):
    lines = [
        '// 由 model/nn_export.py 生成, 不要手改。层表: 硬件按 idx 取这一层的全部参数。',
        'module nn_layers (',
        '    input wire [3:0] idx,',
        '    output reg mode,  // 0 = 普通卷积, 1 = depthwise',
        '    output reg [2:0] k,  // 核大小 1 / 3 / 5',
        '    output reg stride2,',
        '    output reg [6:0] cin,',
        '    output reg [6:0] cout,',
        '    output reg [7:0] in_w,',
        '    output reg [7:0] in_h,',
        '    output reg [7:0] out_w,',
        '    output reg [7:0] out_h,',
        '    output reg relu,',
        '    output reg src_in,  // 1 = 源是输入图像 RAM, 0 = 特征缓冲',
        '    output reg dst_b,   // 0 = 缓冲 A, 1 = 缓冲 B',
        '    output reg [10:0] w_base,',
        '    output reg [9:0] bm_base,',
        '    output reg [5:0] sh,',
        '    output reg signed [7:0] zout,',
        '    output reg signed [7:0] pad_q',
        ');',
        '    always @(*) begin',
        '        case (idx)',
    ]
    for i, la in enumerate(layers):
        lines.append(f'            // {i}: {la["name"]} {la["mode"]} k{la["k"]} s{la["stride"]} '
                     f'{la["cin"]}->{la["cout"]} {la["in_w"]}x{la["in_h"]}->{la["out_w"]}x{la["out_h"]}')
        lines.append(f'            4\'d{i}: begin')
        lines.append(f'                mode = 1\'b{int(la["mode"] == "dw")}; k = 3\'d{la["k"]}; '
                     f'stride2 = 1\'b{int(la["stride"] == 2)};')
        lines.append(f'                cin = 7\'d{la["cin"]}; cout = 7\'d{la["cout"]};')
        lines.append(f'                in_w = 8\'d{la["in_w"]}; in_h = 8\'d{la["in_h"]}; '
                     f'out_w = 8\'d{la["out_w"]}; out_h = 8\'d{la["out_h"]};')
        lines.append(f'                relu = 1\'b{int(la["relu"])}; src_in = 1\'b{int(la["src_in"])}; '
                     f'dst_b = 1\'b{int(la["dst_b"])};')
        lines.append(f'                w_base = 11\'d{la["w_base"]}; bm_base = 10\'d{la["bm_base"]}; '
                     f'sh = 6\'d{la["sh"]};')
        lines.append(f'                zout = 8\'sh{la["zout"] & 0xFF:02x}; pad_q = 8\'sh{la["pad_q"] & 0xFF:02x};')
        lines.append('            end')
    lines += [
        '            default: begin',
        "                mode = 1'b0; k = 3'd1; stride2 = 1'b0; cin = 7'd1; cout = 7'd16;",
        "                in_w = 8'd1; in_h = 8'd1; out_w = 8'd1; out_h = 8'd1;",
        "                relu = 1'b0; src_in = 1'b1; dst_b = 1'b0;",
        "                w_base = 11'd0; bm_base = 10'd0; sh = 6'd0; zout = 8'sh80; pad_q = 8'sh80;",
        '            end',
        '        endcase',
        '    end',
        'endmodule',
    ]
    path.write_text('\n'.join(lines) + '\n')


def emit_tables(qmodel, path):
    head = qmodel['layers'][-1]
    s, z = head['s_out'], head['zout']
    lut = [round(255.0 / (1.0 + np.exp(-(q - z) * s))) for q in range(-128, 128)]
    rows = ',\n    '.join(', '.join(str(v) for v in lut[i : i + 16]) for i in range(0, 256, 16))
    path.write_text(
        '/* 由 model/nn_export.py 生成, 不要手改。handnet 后处理用的常量。 */\n'
        '#ifndef NN_TABLES_H\n'
        '#define NN_TABLES_H\n\n'
        f'#define NN_LAYERS {len(qmodel["layers"])}\n'
        f'#define NN_OUT_W {qmodel["out_w"]}\n'
        f'#define NN_OUT_H {qmodel["out_h"]}\n'
        f'#define NN_OUT_C {qmodel["out_c"]}\n'
        f'#define NN_OUT_WORDS {qmodel["out_w"] * qmodel["out_h"]}\n\n'
        '/* 输出的第 0 个通道是热力图 logit, 它的量化零点是 NN_HEAT_Z: 大于它就等于 sigmoid > 0.5 */\n'
        f'#define NN_HEAT_Z {z}\n\n'
        '/* int8 logit -> 0..255 的概率 (按 head 层的 s、Z 算的 sigmoid) */\n'
        'static const unsigned char nn_sigmoid_lut[256] = {\n    '
        f'{rows}\n'
        '};\n\n'
        '#endif\n'
    )


def calib_from_sessions(path, n=64, seed=7):
    """从录的数据里均匀抽 n 帧当标定画面。用 train.py 缓存的 small_160.npy (160x120, BGR), 转成这里要的 RGB。"""
    caches = [path / 'small_160.npy'] if (path / 'small_160.npy').exists() else sorted(path.glob('*/small_160.npy'))
    if not caches:
        sys.exit(f'{path} 下没有 small_160.npy: 先用这些数据跑一次 model/train.py (它会缓存缩小后的图)')
    frames = np.concatenate([np.load(c) for c in caches])
    pick = np.random.default_rng(seed).choice(len(frames), min(n, len(frames)), replace=False)
    print(f'标定: 从 {len(caches)} 个 session 的 {len(frames)} 帧里抽 {len(pick)} 帧')
    return [frames[i][:, :, ::-1] for i in sorted(pick)]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('ckpt', nargs='?', help='model/train.py 存的 .pt (不给就用固定种子的随机权重)')
    ap.add_argument('--width', type=int, default=16, help='没有 .pt 时的网络宽度 (有 .pt 时从里面读)')
    ap.add_argument('--dw-k', type=int, default=5, choices=[3, 5], help='没有 .pt 时 dw3、dw4 的核大小 (有 .pt 时从里面读)')
    ap.add_argument('--calib', help='标定用的原始画面文件 (每帧 120*160*3 字节, RGB), 或 session / 装着 session 的目录')
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('-o', '--out', default=str(ROOT))
    args = ap.parse_args()
    out = Path(args.out)

    width, dw_k = args.width, args.dw_k
    if args.ckpt:
        import torch

        saved = torch.load(args.ckpt, map_location='cpu')
        width, dw_k = saved['width'], saved.get('dw_k', 3)
        if saved.get('size', 160) != 160 or saved.get('extra', 0) != 0:
            sys.exit(f'{args.ckpt}: 输入 {saved.get("size")}、多 {saved.get("extra", 0)} 块; '
                     f'硬件现在只支持 160 输入、不多加块 (见 docs/hand-model.md "结构试验")')
    layers = spec(width, dw_k)
    ws = make_weights(layers, args.ckpt, args.seed)

    if args.calib and Path(args.calib).is_dir():
        imgs = calib_from_sessions(Path(args.calib))
    elif args.calib:
        raw = np.fromfile(args.calib, dtype=np.uint8)
        n = max(len(raw) // (120 * 160 * 3), 1)
        imgs = [raw[i * 120 * 160 * 3 : (i + 1) * 120 * 160 * 3].reshape(120, 160, 3) for i in range(n)]
    else:
        imgs = calib_images(8)

    per_layer = [[] for _ in layers]
    for img in imgs:
        for i, o in enumerate(forward_float(layers, ws, img)):
            per_layer[i].append((float(o.min()), float(o.max())))
    ranges = [(min(a for a, _ in r), max(b for _, b in r)) for r in per_layer]

    qlayers = quantize(layers, ws, ranges)
    w_words, bm_words = pack_roms(qlayers)
    a_words, b_words = buffer_words(qlayers)

    w_depth, bm_depth = pow2(max(len(w_words), 1)), pow2(max(len(bm_words), 1))
    nn = out / 'rtl/nn'
    nn.mkdir(parents=True, exist_ok=True)
    (nn / 'nn_w.mem').write_text(''.join(f'{v:032x}\n' for v in w_words + [0] * (w_depth - len(w_words))))
    (nn / 'nn_bm.mem').write_text(''.join(f'{v:016x}\n' for v in bm_words + [0] * (bm_depth - len(bm_words))))

    model = {'in_w': 160, 'in_h': 120, 'out_w': layers[-1]['out_w'], 'out_h': layers[-1]['out_h'],
             'out_c': layers[-1]['cout'], 'layers': qlayers}
    (nn / 'nn_model.vh').write_text(
        '// 由 model/nn_export.py 生成, 不要手改。\n'
        f'`define NN_LAYERS {len(qlayers)}\n'
        f'`define NN_IN_W {model["in_w"]}\n'
        f'`define NN_IN_H {model["in_h"]}\n'
        f'`define NN_IN_PIX {model["in_w"] * model["in_h"]}\n'
        f'`define NN_OUT_W {model["out_w"]}\n'
        f'`define NN_OUT_H {model["out_h"]}\n'
        f'`define NN_OUT_C {model["out_c"]}\n'
        f'`define NN_OUT_WORDS {model["out_w"] * model["out_h"]}\n'
        f'`define NN_A_WORDS {a_words}\n'
        f'`define NN_B_WORDS {b_words}\n'
        f'`define NN_W_WORDS {w_depth}\n'
        f'`define NN_BM_WORDS {bm_depth}\n'
        f'`define NN_OUT_BASE {a_words if qlayers[-1]["dst_b"] else 0}\n'
    )
    emit_layers_v(qlayers, nn / 'nn_layers.v')
    (out / 'sw/nn').mkdir(parents=True, exist_ok=True)
    emit_tables(model, out / 'sw/nn/nn_tables.h')

    # 测试向量: 固定的一张"深色背景 + 亮块"图, RTL 和参考实现逐字节比较
    import nnref

    rng = np.random.default_rng(3)
    img = np.zeros((120, 160, 3), dtype=np.uint8)
    img[:] = (18, 20, 24)
    img[30:90, 40:110] = (200, 160, 140)
    img[45:60, 55:70] = (90, 70, 60)
    img = (img.astype(np.int32) + rng.integers(0, 12, img.shape)).clip(0, 255).astype(np.uint8)
    expect = nnref.run(model, img)

    tests = out / 'tests/nn'
    tests.mkdir(parents=True, exist_ok=True)
    (tests / 'in.raw').write_bytes(img.tobytes())
    (tests / 'expect.raw').write_bytes(expect.astype(np.int8).tobytes())
    metas = [{k: v for k, v in la.items() if k not in ('w', 'b', 'm')} for la in qlayers]
    arrays = {}
    for i, la in enumerate(qlayers):
        for key in ('w', 'b', 'm'):
            arrays[f'{key}{i}'] = la[key]
    meta = {'n_layers': len(qlayers), 'layers': metas, 'in_w': 160, 'in_h': 120,
            'out_w': model['out_w'], 'out_h': model['out_h'], 'out_c': model['out_c']}
    np.savez(tests / 'model.npz', meta=np.array(meta, dtype=object), **arrays)

    params = sum(la['cout'] * (la['cin'] // la['groups']) * la['k'] * la['k'] for la in qlayers)
    macs = sum(la['out_w'] * la['out_h'] * la['cout'] * (la['cin'] // la['groups']) * la['k'] * la['k']
               for la in qlayers)
    print(f'{len(qlayers)} 层, {params / 1000:.1f}k 参数, {macs / 1e6:.2f} M 乘加/帧')
    print(f'  缓冲 A {a_words} 字 = {a_words * 16 / 1024:.0f} KiB, B {b_words} 字 = {b_words * 16 / 1024:.0f} KiB')
    print(f'  权重 ROM {w_depth}x128 位 ({len(w_words)} 有效), 乘数/偏置 {bm_depth}x64 位 ({len(bm_words)} 有效)')
    print(f'  测试向量 tests/nn/, 校验和 0x{nnref.checksum(expect):08x}')


if __name__ == '__main__':
    main()
