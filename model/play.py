#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "opencv-python", "mediapipe"]
# ///
"""手势玩弹幕 (东方式) 原型: 先用成熟模型 (MediaPipe) 当输入, 看手势控制到底能不能玩。

用法: model/play.py <gesture_recognizer.task> [摄像头编号或视频文件, 默认 0] [--record <人> <场景>]
  --record: 边玩边录, 和 record.py 一样存 640x480 的帧 (段名 play), 之后用 label.py 标注。
玩法: 握拳移动控制自机, 张开一下放 bomb (清屏, 每条命 3 个); 自动射击, 打中上面的 boss 得分。
  3 条命, 用完后张开手 1 秒或按 R 重开。每局结束在终端打印成绩。
按键: M 切换 手 / 鼠标 (对照: 鼠标也躲不过说明是游戏太难, 不是手势的问题)
      S 平滑开关; 0~3 给手的位置加噪声 (模拟自己模型的误差, 单位是 160x120 画面里的点); Q 退出
画面是 320x240 放大 3 倍, 和板子上的逻辑分辨率一样。右下角是摄像头小窗: 框是有效区, 手在框里就能控制全屏。
"""

import argparse
import json
import math
import random
import sys
import threading
import time

import cv2
import mediapipe as mp
import numpy as np

from label import FIST, PALM, TEACHER, IGNORE, finger_ratios, merge, recognizer, rule
from motion import to_vga
from record import QUALITY, SAVE_EVERY, new_session

W, H = 320, 240  # 逻辑分辨率, 和板子一样
SCALE = 3  # 窗口放大倍数
FPS = 60

ACTIVE = 0.6  # 摄像头画面中间 60% 映射到全屏: 手不用伸到画面边上 (边上 MediaPipe 也容易丢)
SWITCH_FRAMES = 3  # 连续几帧都是另一种手势才切换 (防抖, 单位是摄像头帧, 30 帧/秒时约 0.1 秒)
RESTART_HOLD = 1.0  # 游戏结束后张开手几秒重开
NOISE = [0, 1, 2, 4]  # 按 0~3 选的噪声标准差, 单位: 160x120 画面里的点

LIVES = 3
BOMBS = 3  # 每条命几个 bomb
INVINCIBLE = 2.0  # 被击中或放 bomb 后无敌几秒
PLAYER_R = 2  # 自机判定点半径 (东方式: 判定点比画出来的飞机小得多)
BULLET_R = 3


class Camera(threading.Thread):
    """后台一直读摄像头、跑 MediaPipe; 主循环用 latest() 取最新结果, 不用等识别。"""

    def __init__(self, model, source, record=None):
        super().__init__(daemon=True)
        self.model = model
        self.out = new_session(*record, 'play') if record else None  # 边玩边录存到哪
        self.frames = []  # 录下的帧, 格式同 record.py 的 meta.json
        self.cap = cv2.VideoCapture(int(source) if source.isdigit() else source)
        if not self.cap.isOpened():
            sys.exit(f'打不开摄像头 {source}')
        self.is_file = not source.isdigit()
        self.lock = threading.Lock()
        self.result = (0, None, IGNORE, None, 0.0)  # (第几帧, 手心位置, 手势, 小窗画面, 识别耗时 ms)
        self.running = True

    def stop(self):
        self.running = False
        self.join()
        if self.out:
            meta = {'save_every': SAVE_EVERY, 'expect': {'play': 'maybe'}, 'frames': self.frames}
            meta['person'], meta['scene'] = self.out.name.split('_')[1:3]
            (self.out / 'meta.json').write_text(json.dumps(meta, indent=1, ensure_ascii=False))
            print(f'录了 {len(self.frames)} 帧, 存到 {self.out}')

    def run(self):
        count = 0
        with recognizer(self.model) as detector:
            while self.running:
                ok, frame = self.cap.read()
                if not ok:
                    if self.is_file:  # 视频文件放完从头再来 (测试用)
                        self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                        continue
                    break
                start = time.monotonic()
                # 镜像 (像照镜子: 手往右, 自机往右), 再裁成 4:3 的 640x480: 和录数据、板子 HDMI 输入看到的范围一样
                frame = to_vga(cv2.flip(frame, 1))
                if self.out and count % SAVE_EVERY == 0:
                    file = f'play_{count:05d}.jpg'
                    cv2.imwrite(str(self.out / file), frame, [cv2.IMWRITE_JPEG_QUALITY, QUALITY])
                    self.frames.append({'file': file, 'segment': 'play', 't_ms': int(start * 1000)})
                image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
                found = detector.recognize_for_video(image, int(start * 1000))
                pos, gesture = None, IGNORE
                if found.hand_landmarks:  # 有几只手只看第一只
                    points = found.hand_landmarks[0]
                    pos = np.mean([[points[i].x, points[i].y] for i in PALM], 0)  # 0..1 的比例
                    teacher = TEACHER.get(found.gestures[0][0].category_name, IGNORE)
                    gesture = merge(teacher, rule(finger_ratios(found.hand_world_landmarks[0])))  # 同 label.py
                cost = (time.monotonic() - start) * 1000
                count += 1
                with self.lock:
                    self.result = (count, pos, gesture, frame, cost)

    def latest(self):
        with self.lock:
            return self.result


class OneEuro:
    """One Euro 滤波 (Casiez 2012): 手慢时多平滑 (去抖), 手快时少平滑 (不拖尾)。
    min_cutoff 越小, 手不动时越稳; beta 越大, 手快速移动时跟得越紧。"""

    def __init__(self, min_cutoff=1.0, beta=0.02):
        self.min_cutoff, self.beta = min_cutoff, beta
        self.x = self.speed = self.t = None

    @staticmethod
    def alpha(dt, cutoff):
        """截止频率为 cutoff 的一阶低通滤波, 每步新值占的比例。"""
        return 1 / (1 + 1 / (2 * math.pi * cutoff * dt))

    def __call__(self, x, t):
        if self.x is None:
            self.x, self.speed, self.t = x, np.zeros(2), t
            return x
        dt = max(t - self.t, 1e-3)
        self.t = t
        a = self.alpha(dt, 1.0)
        self.speed = self.speed + a * ((x - self.x) / dt - self.speed)  # 速度也平滑一下, 不然噪声会被当成快速移动
        cutoff = self.min_cutoff + self.beta * np.linalg.norm(self.speed)
        self.x = self.x + self.alpha(dt, cutoff) * (x - self.x)
        return self.x


class Hand:
    """把摄像头结果变成游戏输入: 位置 (屏幕坐标) 和是否握拳。只在摄像头出新帧时更新。"""

    def __init__(self):
        self.seen = 0  # 处理到摄像头第几帧
        self.pos = None  # 屏幕坐标; 没手时保持上一次的位置, 自机原地不动
        self.fist = False  # 防抖之后的手势
        self.streak = 0  # 连续几帧是和 self.fist 相反的手势
        self.filter = OneEuro()
        self.lost_since = None
        self.frames = self.lost = 0  # 统计: 一共几帧, 几帧没找到手
        self.costs = []  # 统计: 每帧识别耗时 ms

    def update(self, camera, noise, smooth):
        count, pos, gesture, _, cost = camera.latest()
        if count == self.seen:
            return
        self.seen = count
        self.frames += 1
        self.costs.append(cost)
        now = time.monotonic()
        if pos is None:
            self.lost += 1
            if self.lost_since is None:
                self.lost_since = now
            if now - self.lost_since > 0.3:  # 丢手久了, 重新出现时不要从旧位置滑过去
                self.filter = OneEuro()
            return
        self.lost_since = None

        # 模拟自己模型的误差: 在 160x120 画面的坐标上加高斯噪声
        x = pos[0] + random.gauss(0, noise) / 160
        y = pos[1] + random.gauss(0, noise) / 120
        # 有效区 (画面中间 ACTIVE 那么大) 映射到全屏
        lo = (1 - ACTIVE) / 2
        screen = np.array([(x - lo) / ACTIVE * W, (y - lo) / ACTIVE * H])
        if smooth:
            screen = self.filter(screen, now)
        self.pos = np.clip(screen, 0, [W - 1, H - 1])

        # 防抖: 连续 SWITCH_FRAMES 帧都是另一种手势才切换, 中间夹一帧原来的手势就重新数;
        # 说不清 (IGNORE) 的帧不算数, 也不打断
        if gesture == IGNORE:
            return
        if (gesture == FIST) != self.fist:
            self.streak += 1
            if self.streak >= SWITCH_FRAMES:
                self.fist = not self.fist
                self.streak = 0
        else:
            self.streak = 0


class Game:
    """一局弹幕。boss 在上面左右移动, 轮流放三种弹幕, 越往后越密。"""

    def __init__(self):
        self.t = 0.0  # 这局开始了几秒
        self.player = np.array([W / 2, H * 0.8])
        self.lives, self.bombs = LIVES, BOMBS
        self.invincible = 0.0
        self.score = 0
        self.bullets = []  # 敌弹: [x, y, vx, vy]
        self.shots = []  # 自机子弹: [x, y]
        self.next_shot = self.next_fire = 0.0
        self.angle = 0.0  # 螺旋弹幕的当前角度
        self.hits = self.bombs_used = 0
        self.over = False

    def boss(self):
        return np.array([W / 2 + 100 * math.sin(self.t * 0.7), 40])

    def fire(self, angle, speed):
        bx, by = self.boss()
        self.bullets.append([bx, by, speed * math.cos(angle), speed * math.sin(angle)])

    def pattern(self):
        """每 5 秒换一种弹幕; 每 30 秒难度加一级 (更多、更快)。"""
        level = 1 + int(self.t // 30)
        kind = int(self.t // 5) % 3
        if self.t < self.next_fire:
            return
        if kind == 0:  # 圆环: 一圈同时射出
            n = 12 + 4 * level
            start = random.random() * math.tau
            for i in range(n):
                self.fire(start + math.tau * i / n, 50 + 10 * level)
            self.next_fire = self.t + 0.8
        elif kind == 1:  # 自机狙: 对准自机的一小扇
            bx, by = self.boss()
            aim = math.atan2(self.player[1] - by, self.player[0] - bx)
            for i in range(-2, 3):
                self.fire(aim + 0.25 * i, 80 + 10 * level)
            self.next_fire = self.t + 0.6
        else:  # 螺旋: 一直转着射
            for i in range(level):
                self.fire(self.angle + math.tau * i / level, 60)
            self.angle += 0.35
            self.next_fire = self.t + 0.06

    def bomb(self):
        if self.bombs > 0 and not self.over:
            self.bombs -= 1
            self.bombs_used += 1
            self.bullets = []
            self.invincible = INVINCIBLE

    def step(self, dt, target):
        if self.over:
            return
        self.t += dt
        self.invincible = max(0.0, self.invincible - dt)
        if target is not None:
            self.player = target.copy()  # 绝对位置: 自机直接到手的位置

        # 自动射击, 打中 boss 得分
        if self.t >= self.next_shot:
            self.shots.append([self.player[0], self.player[1] - 6])
            self.next_shot = self.t + 0.08
        bx, by = self.boss()
        kept = []
        for s in self.shots:
            s[1] -= 300 * dt
            if abs(s[0] - bx) < 16 and abs(s[1] - by) < 12:
                self.score += 10
            elif s[1] > 0:
                kept.append(s)
        self.shots = kept

        # 敌弹移动, 出屏删掉, 碰到判定点就扣命
        self.pattern()
        kept = []
        hit = False
        for b in self.bullets:
            b[0] += b[2] * dt
            b[1] += b[3] * dt
            if -10 < b[0] < W + 10 and -10 < b[1] < H + 10:
                kept.append(b)
                if math.hypot(b[0] - self.player[0], b[1] - self.player[1]) < PLAYER_R + BULLET_R:
                    hit = True
        self.bullets = kept
        if hit and self.invincible == 0:
            self.hits += 1
            self.lives -= 1
            self.bombs = BOMBS
            self.bullets = []
            self.invincible = INVINCIBLE
            self.over = self.lives == 0

    def draw(self):
        """画到 320x240 的图上 (颜色是 OpenCV 的 BGR 顺序)。"""
        screen = np.full((H, W, 3), (40, 16, 16), np.uint8)
        pt = lambda x, y: (int(x), int(y))  # noqa: E731  OpenCV 画图要整数坐标
        cv2.circle(screen, pt(*self.boss()), 12, (200, 60, 200), -1)
        for s in self.shots:
            cv2.line(screen, pt(s[0], s[1]), pt(s[0], s[1] - 4), (255, 220, 150))
        for b in self.bullets:
            cv2.circle(screen, pt(b[0], b[1]), BULLET_R, (90, 90, 255), -1)
            cv2.circle(screen, pt(b[0], b[1]), 1, (230, 230, 255), -1)
        # 自机: 无敌时闪烁; 画出来的三角比判定点 (中间白点) 大
        x, y = self.player
        if self.invincible == 0 or int(self.t * 10) % 2:
            cv2.fillPoly(screen, [np.array([pt(x, y - 7), pt(x - 5, y + 5), pt(x + 5, y + 5)])], (120, 200, 90))
        cv2.circle(screen, pt(x, y), PLAYER_R, (255, 255, 255), -1)
        return screen


def text(window, line, row, color=(255, 255, 255)):
    cv2.putText(window, line, (8, 24 + 26 * row), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)


def draw_preview(window, frame, hand_pos):
    """右下角摄像头小窗, 画出有效区 (黄框) 和识别到的手心 (绿点)。"""
    pw, ph = 240, 180
    x0, y0 = W * SCALE - pw - 8, H * SCALE - ph - 8
    window[y0 : y0 + ph, x0 : x0 + pw] = cv2.resize(frame, (pw, ph))
    lo = (1 - ACTIVE) / 2
    corner = (int(x0 + lo * pw), int(y0 + lo * ph))
    cv2.rectangle(window, corner, (int(corner[0] + ACTIVE * pw), int(corner[1] + ACTIVE * ph)), (0, 255, 255), 1)
    if hand_pos is not None:
        cv2.circle(window, (int(x0 + hand_pos[0] * pw), int(y0 + hand_pos[1] * ph)), 4, (0, 255, 0), -1)


def report(game, mode, noise, smooth, hand):
    lost = f'{hand.lost / hand.frames:.0%}' if hand.frames else '-'
    cost = f'{np.mean(hand.costs):.0f} ms' if hand.costs else '-'
    print(
        f'[{mode} 噪声 {noise} 平滑 {"开" if smooth else "关"}] 坚持 {game.t:.0f} 秒, 得分 {game.score}, '
        f'被击中 {game.hits} 次, 用 bomb {game.bombs_used} 个 | 摄像头 {hand.frames / max(game.t, 1e-3):.0f} 帧/秒, '
        f'没找到手 {lost}, 识别耗时 {cost}'
    )


def main():
    parser = argparse.ArgumentParser(usage=__doc__)
    parser.add_argument('model')
    parser.add_argument('source', nargs='?', default='0')
    parser.add_argument('--record', nargs=2, metavar=('人', '场景'))
    args = parser.parse_args()
    camera = Camera(args.model, args.source, args.record)
    camera.start()

    mouse = {'pos': (W * SCALE // 2, H * SCALE * 4 // 5), 'click': False}

    def on_mouse(event, x, y, flags, param):
        mouse['pos'] = (x, y)
        if event == cv2.EVENT_LBUTTONDOWN:
            mouse['click'] = True

    cv2.namedWindow('play')
    cv2.setMouseCallback('play', on_mouse)

    game, hand = Game(), Hand()
    mode, noise, smooth = 'hand', 0, True
    was_fist = False
    reported = False
    hold = 0.0  # 游戏结束后握拳握了几秒
    last = time.monotonic()
    while True:
        # 定成每秒 FPS 帧: 这一帧剩下的时间等按键
        now = time.monotonic()
        wait = max(1, int((1 / FPS - (now - last)) * 1000))
        key = cv2.waitKey(wait) & 0xFF
        now = time.monotonic()
        dt, last = min(now - last, 0.1), now  # 卡顿时一帧最多算 0.1 秒, 弹幕不会一下跳很远

        if key == ord('q'):
            if not reported:
                report(game, mode, noise, smooth, hand)
            camera.stop()
            return
        if key == ord('m'):
            mode = 'mouse' if mode == 'hand' else 'hand'
        elif key == ord('s'):
            smooth = not smooth
        elif ord('0') <= key <= ord('3'):
            noise = NOISE[key - ord('0')]
        elif key == ord('r') and game.over:
            hold = RESTART_HOLD  # 和握拳握够一样, 下面统一重开

        # 输入: 手或鼠标 -> 自机目标位置; 张开那一下 (从握拳变成张开) 放 bomb
        hand.update(camera, noise, smooth)
        _, raw_pos, _, frame, cost = camera.latest()
        if mode == 'hand':
            target = hand.pos
            if was_fist and not hand.fist:
                game.bomb()
            was_fist = hand.fist
        else:
            target = np.array(mouse['pos'], float) / SCALE
            if mouse['click']:
                game.bomb()
        mouse['click'] = False

        # 游戏结束: 打印成绩; 张开手 RESTART_HOLD 秒重开 (手要在画面里)
        if game.over:
            if not reported:
                report(game, mode, noise, smooth, hand)
                reported = True
            if raw_pos is not None and not hand.fist:
                hold += dt
            elif hold < RESTART_HOLD:  # 握拳或手不见了就重新计时 (按 R 时 hold 已经够了, 不清零)
                hold = 0.0
            if hold >= RESTART_HOLD:
                game, hand = Game(), Hand()
                reported, hold = False, 0.0
                was_fist = False  # 新的 Hand 从张开开始, 握拳后才可能放 bomb

        game.step(dt, target)
        window = cv2.resize(game.draw(), (W * SCALE, H * SCALE), interpolation=cv2.INTER_NEAREST)
        text(window, f'lives {game.lives}  bombs {game.bombs}  score {game.score}  bullets {len(game.bullets)}', 0)
        text(window, f'{mode}  noise {noise}  smooth {"on" if smooth else "off"}', 1)
        if mode == 'hand':
            state = 'no hand' if raw_pos is None else ('FIST' if hand.fist else 'open')
            text(window, f'hand: {state}   detect {cost:.0f} ms', 2, (0, 255, 255))
        if game.over:
            text(window, f'GAME OVER - open hand 1s or press R   {min(hold / RESTART_HOLD, 1):.0%}', 13)
        if frame is not None:
            draw_preview(window, frame, raw_pos)
        cv2.imshow('play', window)


if __name__ == '__main__':
    main()
