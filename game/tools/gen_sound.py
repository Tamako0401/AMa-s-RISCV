#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""程序合成一套音效和一首循环 BGM (16 kHz 16 位 wav), 交给 pack.py 打包。

用法: uv run game/tools/gen_sound.py [输出目录, 默认 game/build/gen-assets]
      uv run game/tools/pack.py --assets game/build/gen-assets
不覆盖已有文件 (要重新生成先删掉)。

音效池只有 12 KiB (16 kHz 8 位 = 0.768 秒), 所以只做短而常响的音效;
bomb / player_hit / fruit_bomb / enemy_explode / start / end 较长, 留给方波 + 噪声合成 (core/sound.c 的表)。
BGM: A 小调 150 BPM, 8 小节 12.8 秒整段循环 (旁边写 .loop.json); 音符尾巴绕回开头, 接缝处没有断音。
电平: BGM 峰值约 0.36, 音效峰值 0.4~0.7, 板上软件混音饱和相加, 叠在一起偶尔削顶。"""

import json
import sys
import wave
from pathlib import Path

import numpy as np

SR = 16000
TOP = 7000  # 带限: 谐波不超过这个频率 (奈奎斯特 8 kHz)
rng = np.random.default_rng(7)


def t_of(n):
    return np.arange(n) / SR


def phase_of(freq):
    """频率 (标量或逐样本数组) -> 累积相位 (弧度)"""
    return 2 * np.pi * np.cumsum(np.broadcast_to(np.asarray(freq, float), (len(np.atleast_1d(freq)),)) / SR)


def sweep(f0, f1, n, curve=1.0):
    k = np.linspace(0, 1, n) ** curve
    return f0 + (f1 - f0) * k


def pulse(freq, duty=0.5, top=TOP):
    """带限脉冲波 (傅里叶级数), freq 是逐样本数组"""
    ph = phase_of(freq)
    out = np.zeros(len(freq))
    for k in range(1, int(top / np.max(freq)) + 1):
        out += np.sin(np.pi * k * duty) / k * np.cos(k * ph - np.pi * k * duty)
    return out * 4 / np.pi / 2


def soft(freq, harmonics=(1, 0.35, 0.12)):
    """正弦加几个谐波, 圆润一点的音色"""
    ph = phase_of(freq)
    return sum(a * np.sin((i + 1) * ph) for i, a in enumerate(harmonics) if (i + 1) * np.max(freq) < TOP)


def noise(n):
    return rng.uniform(-1, 1, n)


def lowpass(x, cutoff):
    """一阶低通; cutoff 可以逐样本变"""
    a = 1 - np.exp(-2 * np.pi * np.broadcast_to(np.asarray(cutoff, float), x.shape) / SR)
    y, s = np.empty_like(x), 0.0
    for i, v in enumerate(x):
        s += a[i] * (v - s)
        y[i] = s
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def env(n, attack=0.002, tau=0.05):
    """快起 + 指数衰减, 最后 2 ms 线性收到 0 (不留咔哒)"""
    t = t_of(n)
    e = np.minimum(1, t / max(attack, 1e-6)) * np.exp(-t / tau)
    tail = min(n, int(0.002 * SR))
    e[n - tail :] *= np.linspace(1, 0, tail)
    return e


def norm(x, peak):
    return x / np.max(np.abs(x)) * peak


def ms(v):
    return int(SR * v / 1000) // 4 * 4  # 4 样本对齐, 打包不补零


# ---- 音效 (总长 10560 样本, 池 12288) ----


def sfx_shot():
    n = ms(60)
    x = pulse(sweep(1250, 760, n, 0.5), 0.25) * env(n, 0.001, 0.018)
    x[:48] += noise(48) * np.linspace(0.6, 0, 48)
    return norm(x, 0.4)


def sfx_graze():
    n = ms(70)
    t = t_of(n)
    x = np.sin(phase_of(sweep(2300, 3300, n))) * (0.6 + 0.4 * np.sin(2 * np.pi * 90 * t))
    x += highpass(noise(n), 3000) * 0.5
    return norm(x * env(n, 0.004, 0.03), 0.4)


def sfx_enemy_hit():
    n = ms(70)
    x = pulse(np.full(n, 320.0), 0.5) * env(n, 0.001, 0.02) + lowpass(noise(n), 2500) * env(n, 0.0005, 0.012) * 1.5
    return norm(x, 0.5)


def sfx_slash():
    n = ms(100)
    t = t_of(n)
    x = lowpass(highpass(noise(n), 800), sweep(6500, 900, n)) * np.sin(np.pi * t / t[-1]) ** 0.7
    return norm(x, 0.6)


def sfx_cut():
    n = ms(100)
    thump = np.sin(phase_of(sweep(190, 70, n, 0.4))) * env(n, 0.001, 0.04)
    ping = soft(np.full(n, 930.0)) * env(n, 0.001, 0.025) * 0.5
    click = lowpass(noise(n), 4000) * env(n, 0.0003, 0.006)
    return norm(thump + ping + click, 0.7)


def sfx_menu_move():
    n = ms(40)
    return norm(pulse(np.full(n, 880.0), 0.25) * env(n, 0.001, 0.015), 0.4)


def sfx_menu_ok():
    n, h = ms(100), ms(40)
    f = np.where(np.arange(n) < h, 660.0, 990.0)
    e = np.concatenate([env(h, 0.001, 0.02), env(n - h, 0.001, 0.03)])
    return norm(pulse(f, 0.5) * e, 0.5)


def sfx_miss():
    n = ms(120)
    t = t_of(n)
    f = sweep(420, 190, n) * (1 + 0.03 * np.sin(2 * np.pi * 25 * t))
    return norm(pulse(f, 0.5, 3000) * env(n, 0.002, 0.06), 0.45)


SFX = {
    'shot': sfx_shot,
    'graze': sfx_graze,
    'enemy_hit': sfx_enemy_hit,
    'slash': sfx_slash,
    'cut': sfx_cut,
    'menu_move': sfx_menu_move,
    'menu_ok': sfx_menu_ok,
    'miss': sfx_miss,
}

# ---- BGM ----

BPM = 150
STEP = SR * 60 // BPM // 4  # 十六分音符 1600 样本
BARS = 8
LEN = STEP * 16 * BARS  # 204800 样本 = 12.8 秒


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


A2, F2, G2, E2 = 45, 41, 43, 40
# 每小节: 低音根音, 琶音的和弦音 (MIDI)
CHORDS = [
    (A2, (69, 72, 76, 81)),  # Am
    (F2, (65, 69, 72, 77)),  # F
    (G2, (67, 71, 74, 79)),  # G
    (E2, (64, 67, 71, 76)),  # Em
    (A2, (69, 72, 76, 81)),  # Am
    (F2, (65, 69, 72, 77)),  # F
    (G2, (67, 71, 74, 79)),  # G
    (E2, (64, 68, 71, 76)),  # E (升 G, 回到 Am)
]
# 旋律: 每小节 (起始十六分, 长度十六分, MIDI)
MELODY = [
    [(0, 4, 69), (4, 2, 72), (6, 2, 76), (8, 4, 74), (12, 4, 72)],
    [(0, 6, 69), (6, 2, 67), (8, 4, 65), (12, 4, 69)],
    [(0, 4, 71), (4, 4, 74), (8, 6, 79), (14, 2, 77)],
    [(0, 8, 76), (8, 4, 74), (12, 4, 71)],
    [(0, 2, 69), (2, 2, 71), (4, 4, 72), (8, 2, 76), (10, 6, 81)],
    [(0, 4, 79), (4, 4, 77), (8, 4, 76), (12, 4, 72)],
    [(0, 4, 74), (4, 4, 76), (8, 4, 77), (12, 4, 74)],
    [(0, 8, 76), (8, 4, 68), (12, 4, 71)],
]


def place(buf, start, sig):
    """加到 buf 里, 超出结尾的部分绕回开头 (整段循环无缝)"""
    idx = (start + np.arange(len(sig))) % len(buf)
    np.add.at(buf, idx, sig)


def note_bass(midi, n):
    f = np.full(n, hz(midi))
    return lowpass(pulse(f, 0.5, 1800), 900) * env(n, 0.003, 0.18)


def note_arp(midi, n):
    return pulse(np.full(n, hz(midi)), 0.125, 5000) * env(n, 0.001, 0.05)


def note_lead(midi, n):
    t = t_of(n)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.15) / 0.1, 0, 1)
    a = np.minimum(1, t / 0.01) * (0.75 + 0.25 * np.exp(-t / 0.08))
    rel = min(n, int(0.03 * SR))
    a[n - rel :] *= np.linspace(1, 0, rel)
    return soft(hz(midi) * vib, (1, 0.45, 0.2, 0.1)) * a


def kick():
    n = ms(140)
    return np.sin(phase_of(sweep(150, 42, n, 0.3))) * env(n, 0.001, 0.07)


def snare():
    n = ms(120)
    return (
        highpass(lowpass(noise(n), 5000), 700) * env(n, 0.001, 0.05)
        + np.sin(phase_of(np.full(n, 190.0))) * env(n, 0.001, 0.03) * 0.5
    )


def hat():
    n = ms(35)
    return highpass(noise(n), 5000) * env(n, 0.0005, 0.012)


def bgm():
    bass, arp, lead, drums = (np.zeros(LEN) for _ in range(4))
    k, s, h = kick(), snare(), hat()
    for bar, (root, tones) in enumerate(CHORDS):
        b0 = bar * 16 * STEP
        for i in range(8):  # 八分音符低音, 根音 / 高八度交替
            place(bass, b0 + i * 2 * STEP, note_bass(root + (12 if i % 2 else 0), 2 * STEP))
        for i in range(16):  # 十六分琶音, 上行再下行
            order = (0, 1, 2, 3, 2, 1, 2, 3)
            place(arp, b0 + i * STEP, note_arp(tones[order[i % 8]], STEP))
        for start, length, midi in MELODY[bar]:
            place(lead, b0 + start * STEP, note_lead(midi, length * STEP))
        for i in (0, 8, 10):
            place(drums, b0 + i * STEP, k)
        for i in (4, 12):
            place(drums, b0 + i * STEP, s)
        for i in range(2, 16, 4):
            place(drums, b0 + i * STEP, h * 0.6)
    mix = bass * 0.30 + arp * 0.10 + lead * 0.30 + drums * 0.35
    echo = np.roll(lead, 3 * STEP) * 0.25  # 旋律加一个八分附点回声, 循环里绕回
    return norm(mix + echo * 0.30, 0.36)


def write(path, x):
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype('<i2')
    with wave.open(str(path), 'wb') as f:
        f.setparams((1, 2, SR, 0, 'NONE', 'not compressed'))
        f.writeframes(pcm.tobytes())


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'build/gen-assets'
    (root / 'sfx').mkdir(parents=True, exist_ok=True)
    (root / 'bgm').mkdir(parents=True, exist_ok=True)
    total = 0
    for name, make in SFX.items():
        path = root / 'sfx' / f'{name}.wav'
        x = make()
        total += len(x)
        if not path.exists():
            write(path, x)
    assert total <= 12 * 1024, total
    path = root / 'bgm' / 'stage.wav'
    if not path.exists():
        write(path, bgm())
        path.with_suffix('.loop.json').write_text(json.dumps({'start': 0, 'end': LEN}) + '\n')
    print(f'{root}: {len(SFX)} 个音效 ({total} 样本, 池 {12 * 1024}), BGM {LEN / SR:.1f} 秒循环')


if __name__ == '__main__':
    main()
