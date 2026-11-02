# handnet 加速器 (rtl/nn/)

[model/handnet.py](../model/handnet.py) 那张网络的 int8 定点硬件实现, 挂在[外设子总线](platform.md)的
`0x4000_6000`。一层一层跑完整个网络, 权重和定点乘数在片上 ROM, 不访问外部存储。
结果和 [model/nnref.py](../model/nnref.py) 的整数参考实现逐字节相同 (由 `tests/nn/nn_tb.sv` 比对)。

```
box4 (vin_pclk) ──> 8x24 异步 FIFO ──┐
CPU 写 IN (一个像素) ────────────────┴─> 输入 RAM 19200 x 32 位 ─┐
                                                ├─> 卷积引擎 16 路 int8 乘加 ──> 特征缓冲 A / B (乒乓)
权重 ROM 1024 x 128 位 ────────────────────────┤                                    │
乘数 / 偏置 ROM 512 x 64 位 ───────────────────┘                                    └─> CPU 读 OUT
```

## 为什么是 MMIO, 不是自定义指令

- 一次推理约 79 万拍 (50 MHz 下 16 ms)。做成长延时指令等于整核停住, 流水线全废; MMIO 启动后
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

核大小 1、3、5 (层表的 `k`), 补边 k/2。

- 累加器 int32; 一个 (输出像素, 通道组) 处理完, 再花约 18 拍做定点化 (三级流水, 每拍进一个通道):
  `q_out = clamp(((acc + bias) * M >> SH) + Z)`, M 每个输出通道一个 int32, SH/Z 每层一个。
- ReLU 层的下限就是 Z (等于实数域 `max(0, x)`); 越界 (padding) 的输入取 `pad_q`, 即该层输入量化里的
  "实数 0"。
- 输入图像的定点化在硬件里做: `q = pixel - 128` (XOR 0x80), 通道顺序 B、G、R, 和 OpenCV 一致。

| 层 | 形状 | 乘加 |
| --- | --- | --- |
| conv0 | 3x3 s2, 3→16, 160x120→80x60 | 2.07 M |
| dw1 / pw1 | 3x3 s2 深度, 16→16; 1x1, 16→32 | 0.17 M / 0.61 M |
| dw2 / pw2 | 3x3 s2 深度, 32→32; 1x1, 32→64 | 0.09 M / 0.61 M |
| dw3 / pw3 | 5x5 深度, 64→64; 1x1, 64→64 | 0.48 M / 1.23 M |
| dw4 / pw4 | 同上 | 0.48 M / 1.23 M |
| head | 1x1, 64→4, 20x15 输出 | 0.08 M |
| 合计 | 15.1k 参数 | **7.06 M 乘加/帧** |

dw3、dw4 原来是 3x3 (6.44 M 乘加, 13.0k 参数)。2026-10-27 改成 5x5: 最后一格看得到的范围从约 47 点变成约 79 点,
手近、手大时漏检减半 (见 [hand-model.md](hand-model.md) "结论记录")。`nn_export.py --dw-k 3` 仍能导出旧结构, RTL 两种都支持。

## 寄存器

| 偏移 | 名字 | |
| --- | --- | --- |
| 0x00 | CTRL | bit0 写 1 开始一次推理; bit1 写 1 清 DONE; bit2 写 1 抓下一完整输入帧, 成功后自动推理 (bit2 优先于 bit0, 忙时均忽略) |
| 0x04 | STATUS | bit0 忙 (含等待/抓帧和启动), bit1 推理完成, bit2 正在等待/抓帧, bit3 抓帧失败, [7:4] 当前层号 |
| 0x08 | IN | 写一个像素 `{8'b0, R, G, B}`, 像素地址自增; 忙时忽略 |
| 0x0C | IN_ADDR | 下一个要写的像素 (0..19199) |
| 0x10 | OUT_ADDR | 要读的输出字 = 格子号 (0..299) |
| 0x14 | OUT | `{握拳, dy, dx, 热力图}` 四个 int8 logit, 低字节是热力图 |
| 0x18 | CYCLE | 上一次推理用了多少拍 |
| 0x1C | VERSION | `0x4e4e_0001` |
| 0x20 | IN_PIX | 输入像素个数 (19200) |

- 接受 START 或 CAPTURE 时清 DONE; 接受 CAPTURE 时同时清抓帧失败位。失败位保持到下次 CAPTURE 或复位。
  抓帧期间 START、CAPTURE 和 IN 写入均忽略, 推理期间也不接受 IN 写入; IN_ADDR 仍是 CPU 的写指针,
  抓帧用独立地址从 0 写到 19199, 不改 CPU 指针。
- 结果在特征缓冲的读口上, **只有空闲 (STATUS.bit0 = 0) 时读得到**。
- 输出是 20x15 个格子, 每格再解出"手心在这一格"的分数、格内偏移和握拳分数; 解码在 CPU 上做
  (`sw/nn/nn_post.h`), 硬件只出 logit。

## 相机抓帧

写 CTRL.bit2 后, 请求翻转位经两级同步进入 `vin_pclk` 域。等请求到达后的下一输入 SOF 才开始选择一帧,
所以请求落在帧中间也不会拿半张图。该帧的 box4 输出通过 8 深度 RGB888 异步 FIFO 进入系统域,
按地址 0..19199 写原有输入 RAM; 存储格式仍是 `{0, R^0x80, G^0x80, B^0x80}`,
低字节起依次 B、G、R, 地址 `y*160+x`。CPU 送图和 `nnref.py` 的格式不变。

此时 RAM 只是待验证输入, 不允许推理。下一输入 SOF 的 `crop.frame_commit` 验证该整帧通过,
且缩小流恰有 19200 点、每行 160 点、SOF/EOL 正确、FIFO 未溢出, 才回传成功。
系统域收到结果并排空 FIFO 后自动 START, 从此相机不再写 RAM, 直到 CPU 再次发 CAPTURE。
FIFO 使用 Gray 指针、双触发器同步; 帧结果在像素域保持, 完成翻转位经三级同步后在系统域取样。
50 MHz 系统域每拍可取一像素, 74.25 MHz 输入最快每四拍一像素, 8 点 FIFO 足以覆盖指针同步延迟。
新增逻辑只在写口和控制路径上, 不改卷积读地址/乘加路径, 不加 PLL。

坏行、迟到的高度变化、尺寸切换或不支持尺寸、点数不足、FIFO 溢出都结束本次抓帧,
置 STATUS.bit3、清 bit2/bit0, 不启动推理、不置 DONE。失败时输入 RAM 可含部分新图,
旧输出结果仍保留; 软件应重新 CAPTURE, 不能对这份输入直接 START。
尺寸不稳定的帧也失败, 不自动重试, 稳定规则仍见 [vision.md](vision.md)。
若输入停止而没有下一 SOF, 硬件继续等待, 不推理; 软件等待函数可以超时返回, 但超时不取消硬件请求,
恢复输入后仍会验证这次请求。复位可终止请求; 没有新增断流计时器。

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

摄像头输入不需要 `frame` 数组或 CPU 搬运:

```c
nn_capture();
if (nn_capture_wait(2000000) == 0) {
    nn_hand_t h;
    nn_decode(&h);
}
```

`nn_capturing()` 查询 STATUS.bit2; `nn_capture_wait(limit)` 同时等抓帧和推理,
返回 0 完成、-1 轮询超时、-2 抓帧失败。`nn_busy()` 包含抓帧等待期。
原有 `nn_load` / `nn_start` / `nn_wait` 不变, `nn_wait` 只等 DONE, 不区分抓帧失败。

`sw/app/nn_demo` 是一个能直接跑的例子: 自己造一张图送进去, 串口打印手的位置、握拳、送图/推理各用了多少拍
和校验和。校验和应当等于 `model/nnref.py` 对同一张图的输出。

## 存储

| 项 | 大小 | 说明 |
| --- | --- | --- |
| 输入 RAM | 75 KiB | 19200 x 32 位, 一个像素一个字 (BGR + 填充) |
| 特征缓冲 A | 75 KiB | 4800 个 128 位字, 最大的一层 (conv0 输出 80x60x16) |
| 特征缓冲 B | 19 KiB | 1200 个字, depthwise 那一层的输出 |
| 权重 ROM | 15.8 KiB | 990 个字 x 128 位 (一拍 16 个输出通道); ROM 深度 1024, 只剩 34 个字, 再加层要扩到 2048 |
| 乘数/偏置 ROM | 3.4 KiB | 432 个字 x 64 位 |
| 合计 | 约 186 KiB | 块 RAM, 100K 板上约占 1/4 |

50K 板放不下: 现有位流的块 RAM 已经用到 89%, 这 186 KiB 是它的 70%。要压到 50K, 可以把 conv0 和 dw1
做成流水 (省掉 A 的 75 KiB), 或者输入只存 RGB565 (省 37 KiB)。

本次相机通路静态估计新增 **约 150..250 LUT / 87 FF / 0 块 RAM / 0 DSP / 0 PLL**:
FIFO 只有 192 bit, 标为 `select_ram` 使用分布式 RAM, 不新增整帧缓冲; FF 包括双域指针、同步器、
帧计数/控制和系统写地址。若 FIFO 被映射为寄存器, 最多再增加 192 FF。
未跑 PDS 综合, 最终资源和 50 MHz 时序须以实现报告为准。

## 时序

仿真实测 (`tests/nn/nn_tb.sv`): 一次推理 **792010 拍** (dw3、dw4 是 3x3 时 753610 拍)。

| 时钟 | 推理 | 加送图 (约 13.7 万拍) |
| --- | --- | --- |
| 50 MHz | 15.8 ms | 18.6 ms (约 54 帧/秒) |
| 100 MHz | 7.9 ms | 9.3 ms |

CPU 送图仍是每个像素约 7 拍; 相机现在可直接写输入 RAM, CPU 只发抓帧命令。
抓帧时延包括等下一帧、传图和等下一 SOF 验证, 取决于输入帧率, 不包含在 CYCLE 中。

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
| `./ama test tests/nn` | CPU 送图后 300 个字和 `model/nnref.py` 逐字节相同; 相机抓帧见下一行 |
| `./ama test tests/nn/capture_tb.sv` | 800x600 / 1280x720 (74.25 MHz), 与独立 crop + 4x4 均值 + XOR 模型逐点比对 19200 个 RGB888 字; 忙时写保护、坏行、高度变化、小尺寸拒绝及恢复 |
| `./ama test tests/nn/capture_cdc_tb.sv` | 半帧断流等待、不足帧拒绝、FIFO 溢出拒绝、抓帧中复位 |
| `./ama test tests/soc` | 接线: VERSION/IN_PIX 读得对、推理能跑完、换一张图校验和会变 |
| `model/nnref.py` | 单独跑一遍参考实现, 和 `tests/nn/expect.raw` 对齐 |

`tests/nn/nn_tb.sv` 加 `+verbose` 会打印每层的尺寸和源缓冲的头几个字, 对不上时能从第一层开始查。

## 板子

- 权重 ROM 用 `$readmemh("rtl/nn/nn_w.mem")` 载入。PDS 的工作目录是 `build/fpga/<板>/`,
  `ama fpga build` 会把 `rtl/nn/*.mem` 按同样的相对路径复制过去; 换别的流程时注意这一点
  (和 `rom.v` 的 `ROM_INIT_FILE` 是同一类约束)。
- `$readmemh` 初始化的存储能不能被综合工具推断成块 RAM 初值, 和 [rom.v](../rtl/perips/rom.v)
  的情况一样, 需要在 PDS 里确认一次。
- 放不下的时候不用改 RTL: `soc_top` 有个参数 `NN` (默认 1), 板顶层 (`mes50hp_top` / `mes2l100hp_top`)
  同名参数透传下去, 在 `sw/app/<程序>/app.toml` 里写 `params = { NN = 0 }` 就整个加速器不综合,
  `0x4000_6000` 变成不握手 (和 `DISPLAY_NEW = 0` 时 s3 的做法一样)。PGL50H 的 134 块 DRM18K 里
  加速器要占约 108 块, 不关掉连基础位流都过不了 device map; `sw/app/camera` 和
  `sw/app/hdmi_colorbar` 就是这么编的 —— 相机监看由 HDMI 直出, 本来也没用到 NN。

## 下一步

1. **相机直连已完成 (仿真)**: box4 经小异步 FIFO 复用系统域输入 RAM 写口, 整帧验证后自动推理。
   仍需 PDS 综合/时序/CDC 检查和板上实际画面验证, 再接应用的抓帧与 `nn_decode` 循环。
2. **省存储**: conv0 → dw1 流水, 省掉 75 KiB 的缓冲 A; 输入改 RGB565 再省 37 KiB。目标是 50K 也能放。
3. **提吞吐**: 现在是"输出通道 16 路并行 + 权重一拍一读", 想快可以缓存权重 (一层只读一次),
   或者把 16 路加宽到 32 路。每帧 7.06 M 乘加, 50 MHz 下理论下限 (128 MAC/拍) 是 5 万拍。
4. **换更大的模型**: 层表是数据, 加 5x5 卷积、平均池化、跳连都只是加一种 mode, 不用改控制结构。
