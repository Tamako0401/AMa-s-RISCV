#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "opencv-python", "mediapipe", "torch"]
# ///
"""把手的识别结果经本机 UDP 发给 C 游戏 (game/pc), 代替板上的视觉寄存器。

用法: model/hand_send.py <gesture_recognizer.task> [摄像头编号或视频文件, 默认 0] [--student 模型 [--threshold 0.5]] [--port 5005]
  摄像头、MediaPipe、自己的模型都和 play.py 一样 (直接用它的 Camera)。
  每出一帧结果发: "HAND" 包 (序号, 有没有手, 握拳 1 / 张开 0 / 说不清 -1, 手心 x, y, 640x480 坐标),
  再分几包发 160x120 的小图 (和硬件一样按块平均缩小), 游戏放在摄像头小窗里。格式见 game/pc/hand_udp.c。
平滑、防抖都在游戏里做 (game/core/hand.c), 这里发原始结果。Ctrl+C 退出。
"""

import argparse
import socket
import struct
import time

from handnet import shrink
from label import FIST, IGNORE
from play import Camera

ROWS = 15  # 小图每包几行

def main():
    parser = argparse.ArgumentParser(usage=__doc__)
    parser.add_argument('model')
    parser.add_argument('source', nargs='?', default='0')
    parser.add_argument('--student')
    parser.add_argument('--threshold', type=float, default=0.5)
    parser.add_argument('--port', type=int, default=5005)
    args = parser.parse_args()

    camera = Camera(args.model, args.source, student=args.student, threshold=args.threshold)
    camera.start()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    print(f'发往 127.0.0.1:{args.port}, Ctrl+C 退出')
    sent = 0
    try:
        while True:
            count, pos, gesture, frame, cost, _, _ = camera.latest()
            if count == sent or frame is None:
                time.sleep(0.003)
                continue
            sent = count
            found = pos is not None
            x, y = (int(pos[0] * 640), int(pos[1] * 480)) if found else (0, 0)
            fist = -1 if gesture == IGNORE else int(gesture == FIST)
            sock.sendto(struct.pack('<4sIbbhh', b'HAND', count, found, fist, x, y), ('127.0.0.1', args.port))
            small = shrink(frame, 160)
            for row in range(0, 120, ROWS):  # 一个包最多约 9 KB
                head = struct.pack('<4sBB', b'HIMG', row, ROWS)
                sock.sendto(head + small[row : row + ROWS].tobytes(), ('127.0.0.1', args.port))
            if count % 30 == 0:
                print(f'第 {count} 帧: {"手 " + str((x, y)) if found else "没有手"}, 识别 {cost:.0f} ms')
    except KeyboardInterrupt:
        pass
    finally:
        camera.stop()


if __name__ == '__main__':
    main()
