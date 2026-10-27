"""手势小网络: 输入缩小后的 RGB 图, 输出手心在哪 + 握拳还是张开。train.py 训练, 以后的评估、试玩也用这里。

结构 (见 docs/hand-model.md "网络"):
  主干: 3x3 普通卷积 (步长 2) + 4 个深度可分离卷积块 (前两个步长 2), 总步长 8; 只有卷积、BN、ReLU。
  试验选项 (见 docs/hand-model.md "结构试验"): dw_k 把不缩小的块的深度卷积换成 5x5, extra 再多加几个不缩小的块,
  都是为了扩大感受野 (手离镜头近时在 160x120 里有 60~80 点大, 默认结构最后一格只看得到约 47 点)。
  头: 1x1 卷积出 4 个通道, 每个输出格:
    0   热力图: 手心在这格的分数 (sigmoid 前)
    1,2 偏移: 手心在格内的位置 (sigmoid 后是 0..1, 从格的左上角量)
    3   手势: 握拳的分数 (sigmoid 后 > 0.5 算握拳)
  160x120 输入 -> 20x15 个格, 每格 8x8 个点。
"""

import numpy as np
import torch
from torch import nn

STRIDE = 8  # 输出一格对应输入多少个点
VGA_W, VGA_H = 640, 480  # 录下来的原图大小


def shrink(vga, w):
    """640x480 缩到 w 宽 (w 要能整除 640): 每 f x f 块取平均, 整数运算, f = 4 时和 rtl/vision/box4.v 一样。"""
    f = VGA_W // w
    h = VGA_H // f
    blocks = vga.astype(np.uint32).reshape(h, f, w, f, 3).sum((1, 3))
    return (blocks // (f * f)).astype(np.uint8)


def conv_bn(cin, cout, kernel, stride=1, groups=1):
    return nn.Sequential(
        nn.Conv2d(cin, cout, kernel, stride, kernel // 2, groups=groups, bias=False),
        nn.BatchNorm2d(cout),
        nn.ReLU(inplace=True),
    )


def separable(cin, cout, stride, k=3):
    """深度可分离卷积 (MobileNet): kxk 深度卷积 (每个通道各卷各的) + 1x1 卷积 (混合通道)。"""
    return nn.Sequential(conv_bn(cin, cin, k, stride, groups=cin), conv_bn(cin, cout, 1))


class HandNet(nn.Module):
    def __init__(self, width=8, dw_k=3, extra=0):
        """dw_k: 不缩小的块里深度卷积的核大小 (3 或 5); extra: 额外的不缩小的块数。硬件支持 dw_k 3 和 5 (rtl/nn 的层表), extra 只能是 0。"""
        super().__init__()
        w = width
        self.body = nn.Sequential(
            conv_bn(3, w, 3, 2),  # /2
            separable(w, 2 * w, 2),  # /4
            separable(2 * w, 4 * w, 2),  # /8
            # 不缩小, 只扩大感受野 (一格能看到手周围多大范围), 帮助分清手和脸
            *[separable(4 * w, 4 * w, 1, dw_k) for _ in range(2 + extra)],
        )
        self.head = nn.Conv2d(4 * w, 4, 1)

    def forward(self, x):
        """x: N x 3 x H x W 的 uint8 图, 通道顺序和 OpenCV 一样是 BGR。返回 N x 4 x H/8 x W/8, 都是 sigmoid 之前的值。"""
        x = x.float() / 255 - 0.5
        return self.head(self.body(x))


def decode(out):
    """网络输出 (一张图的 4 x GH x GW) -> (分数, 手心 x, y (0..1 的比例), 握拳概率)。取热力图最高的那格。"""
    heat = torch.sigmoid(out[0])
    gh, gw = heat.shape
    k = int(heat.argmax())
    cy, cx = divmod(k, gw)
    dx, dy = torch.sigmoid(out[1:3, cy, cx]).tolist()
    return float(heat[cy, cx]), (cx + dx) / gw, (cy + dy) / gh, float(torch.sigmoid(out[3, cy, cx]))


def save(path, model, width, size, dw_k=3, extra=0):
    torch.save({'state': model.state_dict(), 'width': width, 'size': size, 'dw_k': dw_k, 'extra': extra}, path)


def load(path):
    """读 train.py 存的模型, 返回 (模型, 输入宽度)。"""
    saved = torch.load(path, map_location='cpu')
    model = HandNet(saved['width'], saved.get('dw_k', 3), saved.get('extra', 0))
    model.load_state_dict(saved['state'])
    return model.eval(), saved['size']


def macs(model, w, h):
    """每帧乘加次数和参数个数 (只数卷积)。"""
    total = 0

    def count(m, inp, out):
        nonlocal total
        total += out.numel() * m.in_channels // m.groups * m.kernel_size[0] * m.kernel_size[1]

    hooks = [m.register_forward_hook(count) for m in model.modules() if isinstance(m, nn.Conv2d)]
    model.eval()
    with torch.no_grad():
        model(torch.zeros(1, 3, h, w, dtype=torch.uint8))
    for hook in hooks:
        hook.remove()
    return total, sum(p.numel() for p in model.parameters())
