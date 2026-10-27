# 新显示 (720p)

`rtl/display/`, 计划见 [display-plan.md](display-plan.md)。画法的规格是 `game/tools/refmodel.py` 开头的说明,
这里是寄存器、存储布局和硬件结构。**已例化进 `soc_top`** (rib s3, `0x3000_0000`; `DISPLAY_NEW` 参数为 1 时才接, 这时视频输出口和小窗读由它驱动), 但还没上板。
板上 74.25 MHz 已有 (`mes2l100hp` 的第二个 GPLL, `VIDEO_720P=1` 时)。
旧的 640x480 显示 (`rtl/perips/video.v`, [video.md](video.md)) 不动, `DISPLAY_NEW=0` 即退回。

画面 640x360, 每点放大成 2x2 输出 1280x720@60; 从下到上: 底色 -> 背景 (8x8 图块, 可卷动, 只在游戏区内) -> 摄像头小窗 ->
精灵 (最多 512 个, 每行最多 128 个; 旋转缩放、翻转、半透明 / 加法混合) -> 整体混色 -> 文字层 (1280x720 原生, 8x16 一格)。
游戏那边的接口是 `game/core/gfx.h`, 和这里一一对应。

## 地址 (相对从设备基址)

| 偏移 | 内容 | 说明 |
| --- | --- | --- |
| `0x0_0000` | 寄存器 | 见下表, 可读 |
| `0x0_1000` | 调色板 | 256 项 RGB565, 每项一个字。图案的色号 0 是透明, 0 号这项不用 |
| `0x0_2000` | 图案表 | 1024 项, 每项 {尺寸码[15:13], 起始字[12:0]}; 尺寸码 1/2/3/4 = 边长 8/16/32/64, 0 = 没有这张图 |
| `0x0_4000` | 精灵表 (后台那份) | 512 个, 每个两个字 (地址 `8i`、`8i+4`), 见下 |
| `0x1_0000` | 背景图块表 | 64x64 格 (`4 * (行 * 64 + 列)`), 每格一个图案编号 (必须是 8x8 的图) |
| `0x2_0000` | 文字层 | 160x45 格 (`4 * (行 * 160 + 列)`), 每格 {颜色[11:8], 字符[7:0]}; 字符 33~127 才画, 颜色是 CGA 16 色 |
| `0x3_0000` | 字库 | 128 个字 x 16 行 (`4 * (字 * 16 + 行)`), 每行一个字节, 最高位在左 |
| `0x4_0000` | 图案库 | 64 KB: 每 8 个点一个 64 位字, 左边的点在低字节; 字 w 的低 32 位在 `8w`、高 32 位在 `8w+4`。每张图按行存, 一行 边长/8 个字 |

内存只能整字写, 读回 0 (读口给渲染用)。

| 寄存器 | 偏移 | 内容 |
| --- | --- | --- |
| CTRL | `0x00` | bit0 开显示 (关时输出黑), bit1 开小窗 |
| BACKDROP | `0x04` | 底色 RGB565 |
| CLIP | `0x08` | 游戏区 [9:0] x0, [25:16] x1 (x0 <= x < x1); 背景和带 CLIP 的精灵只画在里面 |
| WINDOW | `0x0C` | 小窗左上角 [11:0] x, [27:16] y, 12 位有符号 (可以半出屏) |
| SCROLL | `0x10` | 背景卷动 [8:0] x, [24:16] y (按 512 绕回) |
| FADE | `0x14` | 整体混色: [15:0] 颜色, [20:16] 程度 0~16 |
| SPRITE_N | `0x18` | 精灵表里有几个 (最多 512) |
| COMMIT | `0x1C` | 写 1: 提交这一帧; 读: 1 = 还没生效 |
| STATUS | `0x20` | bit0 场消隐期 (只读) |
| FRAME | `0x24` | 帧计数 (只读) |
| LINE_MAX | `0x28` | 上一帧最忙一行用了几拍 (只读; 一行可用约 2222 拍) |
| OVERRUN | `0x2C` | 没在显示前画完的行数, 累计 (只读) |
| DROPPED | `0x30` | 因为一行超过 128 个而丢掉的对象数, 累计 (只读) |

精灵: w0 = {scale[31:24], y[23:12], x[11:0]}, w1 = {angle[31:24], alpha[20:16], flags[15:10], image[9:0]}。
x、y 是中心, 12 位有符号; flags 同 `gfx.h` (ALPHA 1, ADD 2, FLIP_X 4, FLIP_Y 8, AFFINE 16, CLIP 32)。
**先写 w0 再写 w1**: 写 w1 时硬件用刚写的 w0 和图案表算出外框的上下边 (所以图案表要先写好)。

## 每帧怎么用

1. 开机写一次: 调色板、图案表、图案库、字库 (`refmodel.py export` 的 `writes.hex` 就是这个顺序)。
2. 每帧: 读 COMMIT 等它变 0 (上一帧已经换上去) -> 从头写精灵表 -> 写 SPRITE_N、SCROLL、FADE 等 -> COMMIT 写 1。
3. 提交后的下一个场消隐开头 (第 720 条物理行), 精灵表前后台交换, CTRL ~ SPRITE_N 一起换成新值。没提交就一直显示上一帧。
   背景图块表、文字层、调色板、图案直接写, 立刻生效 (游戏是"改了才写")。

## 结构

两个时钟: `clk` (50 MHz, CPU 写、渲染) 和 `pclk` (74.25 MHz, 扫描、文字层)。

```
display.v        总线、寄存器、提交; "第几对物理行开始了" 从 pclk 域同步过来 (toggle), 分派给下面
disp_timing      pclk: 1650x750 计数
disp_sprites     精灵表两份 + Y 范围表 (写 w1 时算外框上下边)
disp_scan        Y 分桶: 每行扫一遍 Y 范围表, 把和这一行相交的编号写进对象列表 (两份按行号奇偶轮换, 每份 128 项)
disp_render      画一行: 背景 (81 个图块拼 80 格) -> 小窗 (一拍一点) -> 列表里的对象; 产出"格子" (8 个点)
  disp_span        不旋转: 一拍一格, 相邻两个图案字拼出一格, FLIP_X 倒着读
  disp_affine      旋转缩放: 一拍一点, u、v 沿行只做加法, 凑满一格交出
disp_blend       格子写回: 查调色板 (8 个读口, disp_palette) + 读工作行 -> 混合 -> 写工作行和显示行; 同一格紧挨着来时前递
disp_scanout     pclk: 读显示行 -> 整体混色 -> RGB888 -> 盖文字层
```

每逻辑行 (两条物理行, 约 2222 个 clk): 显示第 n 行时渲染第 n+1 行、扫描第 n+2 行。
渲染一行的拍数: 背景和判断小窗约 87; 小窗每点 1; 对象准备 5 拍 (旋转 7 拍), 和画上一个重叠;
不旋转画 格数 + 2, 旋转画 点数 + 1。`refmodel.py cost --rtl` 按这个算, 和仿真的 LINE_MAX 差 1 拍以内。

## 仿真

`./ama test tests/display`: 参考模型先导出数据和期望画面 (`refmodel.py export`, 在 tests.toml 的 `prepare` 里),
`display_tb` 走总线写进去、提交、收一整帧, 和期望**逐点比**, 一个点不一样就失败 (存 `got.ppm` 对照)。
场景是 `refmodel.py` 的 `make_scenes` (每种功能和边界) 加两个游戏最难时最忙的一帧 (`tests/display/frames/`)。

2026-10-24 结果, 全部逐点一致:

| 场景 | 内容 | 最忙一行 (拍, 共 2222) |
| --- | --- | --- |
| bg | 只有背景, 卷动绕回, 游戏区 101~547 | 88 |
| window | 小窗半出屏、文字层 16 色和不画的字符、整体混色 5 档 | 212 |
| sprites | 178 个: 各尺寸、翻转、三种混合、CLIP、四边半出屏、同一格连着叠 | 215 |
| affine | 74 个旋转缩放: 随机角度和缩放、翻转 + 旋转、scale 0、放大 16 倍 | 1184 |
| overflow | 600 个 (超过 512 的不画), 一行 300 个 (超过 128 的丢掉) | 860 |
| touhou | 东方式难度 9 最忙一帧, 359 个精灵, 一行最多 85 个 | 765 (34%) |
| fruit | 水果忍者难度 10 最忙一帧 | 1530 (69%) |

故意改坏混合的饱和或 span 的拼接偏移, 比对能查出来 (上千个点不一致)。

## 还没做

- C 的板上后端 (`gfx.h` -> 这些寄存器)、综合 (`mes2l100hp`, `DISPLAY_NEW=1`) 和上板。
- 综合看资源和时序: 调色板现在是 8 份 256x16, 可改 4 份真双口; 行缓存 128 位宽。
- 超时 (OVERRUN) 时那一行是半成品; 现在的游戏最坏 69%, 还有余量。

**SoC 级仿真已过** (2026-10-26, `tests/soc/display_tb.sv`): CPU 走 rib s3 按 `refmodel.py
export --soc` 压出来的脚本把一帧写进显示、提交、轮询生效, `video_sink` 收两帧和 `expect.hex`
逐点比。场景 bg / sprites / affine / overflow (小窗关的四个; 小窗要视觉输入, 以后接
`video_source` 再加 touhou/fruit) 4/4 全过, LINE_MAX 和上表一致。

## PDS 综合段错误 (阻塞 `mes2l100hp` 的 `DISPLAY_NEW=1`)

PDS 2022.2-SP6.4 (ADS 综合器) 综合新显示时稳定段错误 (signal 11, "Flow-0189: Internal
error"), 崩在 synthesize 的 RAM 常量传播/装配阶段, 附近日志总是 `Constant propagation done on
u_sprites/u_w1/mem`。触发者是 `disp_sprites` 的精灵表: **两块 32x1024 的 dpram (u_w0/u_w1,
共享写地址/写数据/读地址、互补写使能)**。`DISPLAY_NEW=0` 的基线综合完全正常 (位流时序
video_pll_clk +0.356), 只有带上精灵表才崩。

二分定位 (最小复现: `build/fpga/disp_bisect/mini.tcl`, 只含 display 的 PDS 工程, 13 秒崩):

- stub 掉 `disp_sprites` -> 不崩; 其它子模块全真只 stub 它 -> 也不崩
- 保留单块 u_w0 (vD)、或把 u_yrange 加宽到 32 位 (vP2) 都不崩 -- 触发要"精灵表这对"特定形态

已排除的绕法 (全部仍崩): 写使能直连 (vJ) / u_w1 改 33、64 位宽 (vH, vAR -- 64 宽反而印证
崩点是"宽 RAM 装配/级联"路径) / 深度 1025 (vN) / dpram 换 dpram2c (vE, vAC) / 写数据加 XOR
掩码 (vX) / w1 的 bank 排布镜像 (vAB) / 写口整体打一拍 (vAQ) / 读地址各挂独立寄存器 (vAS,
被寄存器合并穿透) / 同名 wrapper 隔层次 (vM) / `syn_hier="fixed"` (vAN) / `syn_ramstyle`
no_rw_check、block_ram,low_power (实例上 vAE/vAF, mem 信号上 vAG)。
已排除的综合开关: `-selected_syn_tool_opt 1`、`-resource_sharing FALSE`、
`-enable_prepacking FALSE`、`-pipelining FALSE`、`-rw_check_on_ram`、`-max_parallel_jobs 1`;
SP1-Lite 的综合器不认 Logos2, 换不了。

可行方向 (按推荐顺序): ① 给 Pango 提工单 (16 个文件 + tcl 的最小复现已就绪); ② PDS 新版本
试修没修; ③ 精灵表用 `GTP_DRM36K_E1` 原语直例化绕开推断 (黑盒原语不进装配 pass; 参数可从
`PDS_2022.2-SP6.4/ip/module_ip/ipm2l_flex_ram/.../ipm2l_dpram_v1_9.v.xml` 模板反推; 仿真用
`ifdef VERILATOR` 走 dpram、综合走原语, 参考 `mes2l100hp_top.v` 里 GPLL 的双路径做法,
Verilator 没有原语模型必须双路径)。`mes2l100hp_top.v` 的 `DISPLAY_NEW` 默认 0, 绕过后翻 1。

### 最小复现 (13 秒崩, 供工单 / 队友验证)

新建目录 `mini/` (相对仓库根), 放一个 `mini.tcl`, 用仓库根的
`C:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe -file mini.tcl` 跑:

```tcl
set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676
add_design {../rtl/utils/gen_dff.v}
add_design {../rtl/utils/gen_buf.v}
add_design {../rtl/utils/gen_ram.v}
add_design {../rtl/utils/vld_rdy.v}
add_design {../rtl/utils/dpram.v}
add_design {../rtl/utils/dpram2c.v}
add_design {../rtl/display/disp_timing.v}
add_design {../rtl/display/disp_palette.v}
add_design {../rtl/display/disp_span.v}
add_design {../rtl/display/disp_affine.v}
add_design {../rtl/display/disp_render.v}
add_design {../rtl/display/disp_blend.v}
add_design {../rtl/display/disp_scanout.v}
add_design {../rtl/display/disp_scan.v}
add_design {../rtl/display/disp_sprites.v}
add_design {../rtl/display/display.v}
compile -top_module display -include_path {..}
synthesize -ads -selected_syn_tool_opt 2
```

约 13 秒后 `pds_shell received signal 11` + `Flow-0189: Internal error`。把
`disp_sprites.v` 换成"删掉 u_w0/u_w1 两块 dpram 例化"的版本即可对比出不崩。
