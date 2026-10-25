# handnet 加速器 (rtl/nn/)

[model/handnet.py](../model/handnet.py) 那张网络的 int8 定点硬件实现, 挂在[外设子总线](platform.md)的
`0x4000_6000`。一层一层跑完整个网络, 权重和定点乘数在片上 ROM, 不访问外部存储。
结果和 [model/nnref.py](../model/nnref.py) 的整数参考实现逐字节相同 (由 `tests/nn/nn_tb.sv` 比对)。

```
CPU 写 IN (一个像素) ──> 输入 RAM 19200 x 32 位 ─┐
                                                ├─> 卷积引擎 16 路 int8 乘加 ──> 特征缓冲 A / B (乒乓)
权重 ROM 1024 x 128 位 ────────────────────────┤                                    │
乘数 / 偏置 ROM 512 x 64 位 ───────────────────┘                                    └─> CPU 读 OUT
```

## 为什么是 MMIO, 不是自定义指令

- 一次推理约 72 万拍 (50 MHz 下 14 ms)。做成长延时指令等于整核停住, 流水线全废; MMIO 启动后
  CPU 可以接着跑游戏, 下一帧再取结果。
- 图像和结果本来就要用 MMIO (或以后的 DMA) 搬, 自定义指令只能省掉"启动"那一次 store。
- 赛题允许扩展指令集 [Q9][Q79]。以后想要一条 `nn.start` 的语法糖随时可以加, 现在没必要。

## 计算方式

层表由 `model/nn_export.py` 生成 ([rtl/nn/nn_layers.v](../rtl/nn/nn_layers.v)), 硬件不认识 "handnet",
只认每条记录的 (普通卷积 / depthwise, 核大小, 步长, 通道数, 尺寸, 权重基址, 移位, 量化零点)。

| | 怎么并行 | 一拍做的事 |
| --- | --- | --- |
| 普通卷积 | 16 个**输出通道**并行 | 一个抽头 (输入通道 + 核内位置), 输入字节广播给 16 路 |
| depthwise | 16 个**通道**并行 | 一个核内位置, 每路取自己通道的字节 |

- 累加器 int32; 一个 (输出像素, 通道组) 处理完, 再花 16 拍做定点化:
  `q_out = clamp(((acc + bias) * M >> SH) + Z)`, M 每个输出通道一个 int32, SH/Z 每层一个。
- ReLU 层的下限就是 Z (等于实数域 `max(0, x)`); 越界 (padding) 的输入取 `pad_q`, 即该层输入量化里的
  "实数 0"。
- 输入图像的定点化在硬件里做: `q = pixel - 128` (XOR 0x80), 通道顺序 B、G、R, 和 OpenCV 一致。

| 层 | 形状 | 乘加 |
| --- | --- | --- |
| conv0 | 3x3 s2, 3→16, 160x120→80x60 | 2.07 M |
| dw1 / pw1 | 3x3 s2 深度, 16→16; 1x1, 16→32 | 0.17 M / 0.61 M |
| dw2 / pw2 | 3x3 s2 深度, 32→32; 1x1, 32→64 | 0.09 M / 0.61 M |
| dw3 / pw3 | 3x3 深度, 64→64; 1x1, 64→64 | 0.17 M / 1.23 M |
| dw4 / pw4 | 同上 | 0.17 M / 1.23 M |
| head | 1x1, 64→4, 20x15 输出 | 0.08 M |
| 合计 | 13.0k 参数 | **6.44 M 乘加/帧** |

## 寄存器

| 偏移 | 名字 | |
| --- | --- | --- |
| 0x00 | CTRL | bit0 写 1 开始一次推理 (忙时忽略); bit1 写 1 清 DONE |
| 0x04 | STATUS | bit0 忙, bit1 完成, [7:4] 当前层号 |
| 0x08 | IN | 写一个像素 `{8'b0, R, G, B}`, 像素地址自增 |
| 0x0C | IN_ADDR | 下一个要写的像素 (0..19199) |
| 0x10 | OUT_ADDR | 要读的输出字 = 格子号 (0..299) |
| 0x14 | OUT | `{握拳, dy, dx, 热力图}` 四个 int8 logit, 低字节是热力图 |
| 0x18 | CYCLE | 上一次推理用了多少拍 |
| 0x1C | VERSION | `0x4e4e_0001` |
| 0x20 | IN_PIX | 输入像素个数 (19200) |

- 结果在特征缓冲的读口上, **只有空闲 (STATUS.bit0 = 0) 时读得到**。
- 输出是 20x15 个格子, 每格再解出"手心在这一格"的分数、格内偏移和握拳分数; 解码在 CPU 上做
  (`sw/nn/nn_post.h`), 硬件只出 logit。

## C 库

[sw/nn/nn.h](../sw/nn/nn.h) 是寄存器访问, [sw/nn/nn_post.h](../sw/nn/nn_post.h) 是解码; 都是 header-only,
不用改链接脚本:

```c
uint8_t frame[NN_IN_BYTES]; /* 160*120*3, 行优先 RGB888 */

nn_load(frame);             /* 送图, 约 13.7 万拍 */
nn_start();
if (nn_wait(1000000) == 0) {
    nn_hand_t h;
    nn_decode(&h);          /* h.found / h.x / h.y (160x120) / h.fist / h.heat */
}
```

`sw/app/nn_demo` 是一个能直接跑的例子: 自己造一张图送进去, 串口打印手的位置、握拳、送图/推理各用了多少拍
和校验和。校验和应当等于 `model/nnref.py` 对同一张图的输出。

## 存储

| 项 | 大小 | 说明 |
| --- | --- | --- |
| 输入 RAM | 75 KiB | 19200 x 32 位, 一个像素一个字 (BGR + 填充) |
| 特征缓冲 A | 75 KiB | 4800 个 128 位字, 最大的一层 (conv0 输出 80x60x16) |
| 特征缓冲 B | 19 KiB | 1200 个字, depthwise 那一层的输出 |
| 权重 ROM | 13.8 KiB | 862 个字 x 128 位 (一拍 16 个输出通道) |
| 乘数/偏置 ROM | 3.4 KiB | 432 个字 x 64 位 |
| 合计 | 约 186 KiB | 块 RAM, 100K 板上约占 1/4 |

50K 板放不下: 现有位流的块 RAM 已经用到 89%, 这 186 KiB 是它的 70%。要压到 50K, 可以把 conv0 和 dw1
做成流水 (省掉 A 的 75 KiB), 或者输入只存 RGB565 (省 37 KiB)。

## 时序

仿真实测 (`tests/nn/nn_tb.sv`): 一次推理 **723010 拍**。

| 时钟 | 推理 | 加送图 (约 13.7 万拍) |
| --- | --- | --- |
| 50 MHz | 14.5 ms | 17.2 ms (约 58 帧/秒) |
| 100 MHz | 7.2 ms | 8.6 ms |

送图现在是 CPU 一个一个像素写, 每个约 7 拍; 相机接进来以后应该由视觉前端直接写输入 RAM (见"下一步")。

## 怎么换权重

```sh
model/nn_export.py                       # 没有 .pt 时用固定种子生成 (RTL 照样能验证)
model/nn_export.py model/runs/x.pt       # 用 train.py 存的权重 (需要 torch)
model/nn_export.py --calib frames.raw    # 用真实画面标定量化范围 (每帧 120*160*3 字节)
```

生成的东西都在仓库里 (不用每次跑):

| 文件 | 内容 |
| --- | --- |
| `rtl/nn/nn_model.vh` | 层数、输入输出尺寸、各缓冲深度 |
| `rtl/nn/nn_layers.v` | 层表 (纯组合常量) |
| `rtl/nn/nn_w.mem` | 权重 |
| `rtl/nn/nn_bm.mem` | 每个输出通道的 {int32 乘数, int32 偏置} |
| `sw/nn/nn_tables.h` | sigmoid 查表、输出尺寸 |
| `tests/nn/in.raw`、`expect.raw`、`model.npz` | 测试向量和参考模型 |

量化的具体式子 (`s_in`、`s_w`、`Z` 的定义, 以及 bias 里为什么要减 `Z_in·Σw`) 写在
[model/nn_export.py](../model/nn_export.py) 开头。RTL 只做整数运算, 不碰浮点。

## 验证

| 测试 | 查什么 |
| --- | --- |
| `./ama test tests/nn` | 加速器内部: 走总线送一帧, 300 个字和 `model/nnref.py` 逐字节相同 |
| `./ama test tests/soc` | 接线: VERSION/IN_PIX 读得对、推理能跑完、换一张图校验和会变 |
| `model/nnref.py` | 单独跑一遍参考实现, 和 `tests/nn/expect.raw` 对齐 |

`tests/nn/nn_tb.sv` 加 `+verbose` 会打印每层的尺寸和源缓冲的头几个字, 对不上时能从第一层开始查。

## 板子

- 权重 ROM 用 `$readmemh("rtl/nn/nn_w.mem")` 载入。PDS 的工作目录是 `build/fpga/<板>/`,
  `ama fpga build` 会把 `rtl/nn/*.mem` 按同样的相对路径复制过去; 换别的流程时注意这一点
  (和 `rom.v` 的 `ROM_INIT_FILE` 是同一类约束)。
- `$readmemh` 初始化的存储能不能被综合工具推断成块 RAM 初值, 和 [rom.v](../rtl/perips/rom.v)
  的情况一样, 需要在 PDS 里确认一次。

## 下一步

1. **相机直连**: `rtl/vision/` 的 `box4` 已经输出 160x120 的 RGB888 像素流。给输入 RAM 加一个
   像素时钟的写口 (双时钟 RAM), CPU 就只用写一个"用视觉输入"的位, 省掉 13.7 万拍的送图。
2. **省存储**: conv0 → dw1 流水, 省掉 75 KiB 的缓冲 A; 输入改 RGB565 再省 37 KiB。目标是 50K 也能放。
3. **提吞吐**: 现在是"输出通道 16 路并行 + 权重一拍一读", 想快可以缓存权重 (一层只读一次),
   或者把 16 路加宽到 32 路。每帧 6.44 M 乘加, 50 MHz 下理论下限 (128 MAC/拍) 是 5 万拍。
4. **换更大的模型**: 层表是数据, 加 5x5 卷积、平均池化、跳连都只是加一种 mode, 不用改控制结构。
