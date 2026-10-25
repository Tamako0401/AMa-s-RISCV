# HDMI 720p 与自动输入裁剪验证 (2026-10-23)

工作分支 `hdmi-720p`, 板卡范围仅 MES50HP/PGL50H。没有 PDS、板子或厂商 HDMI 例程,
本记录中的通过均是仿真/静态检查, 不代表已出位流或上板通过。

## 改动边界

1. 输出: 320x240 渲染器保持原样, 720p 扫描放大 3x3、左右各 160 黑边;
   VGA 编译参数回退。行缓存和调色板双时钟, 请求/配置握手, 帧事件与场消隐同步, 小窗读口跟随扫描时钟。
2. 输入: 按完整帧测量有效尺寸, 连续两帧一致才启用中心 640x480 裁剪;
   后台小窗和颜色累加结果等下一 SOF 验证通过后才发布。坏行、尺寸变化和过小输入不发布结果。
3. 测试: SoC、板级测试均按 `VIDEO_720P=0/1` 运行, 同步调整截图外壳。

## 本机命令和结果

环境原先没有可调用的 Verilator/RISC-V GCC。本次安装 Homebrew `verilator` 5.052、
`riscv64-elf-gcc` 16.2.0 (含 rv32i/ilp32 multilib), 在不提交的 `ama.local.toml` 中配置
`riscv32-unknown-elf-gcc = ["riscv64-elf-gcc"]`。
已知的 `__mulsi3` 缺失在这套工具链未复现, 没有为此改 RTL 或固件算法。

| 命令 | 结果 |
| --- | --- |
| `./ama test` | 62 PASS / 0 FAIL, 291.70 s; 包含原有预期失败测试, 按测试配置视为 PASS |
| `./ama test tests/video/scan_tb.sv` | VGA/720p 共 2 PASS: 全部物理像素、黑边、2x2/3x3、滚动背景、64 同行精灵、小窗、同步宽度和周期、FRAME/STATUS |
| `./ama test tests/video/input_tb.sv` | 三种输入: 800x600、1280x720、640x480; 全部 19200 小窗像素、全命中统计/坐标和、坏行、迟到的高度变化、320x240 拒绝、恢复 |
| `./ama test tests/soc/video_tb.sv` | VGA/720p 均 PASS, 真实 video_demo; 颜色命中 122, 坐标和 (10013,14054) |
| `./ama sim video_demo --vga --frames 5` | 保存 640x480 PNG, 已查看 |
| `./ama sim video_demo --frames 5` | 保存 1280x720 PNG, 已查看; 左右各 160 黑边, 游戏画面/小窗正常 |
| `ruff check tools/ama/cli.py sim/view.py` | PASS |
| `ruff format --check tools/ama/cli.py sim/view.py` | PASS |
| `git diff --check` | PASS |

扫描仿真里 64 个精灵全部命中时, 最后一次缓存写入为启动后第 1732 拍。
保守预算仍按 1733 拍再加约 4 拍跨域延迟; 720p 每逻辑行 3333.33 拍, 余量约 1596 拍。

另用 Icarus 确认生产 RTL 可用 Verilog 2005 解析, 避免把 SystemVerilog 强制转换语法引入 `.v`:

```sh
iverilog -g2005 -s video -o /tmp/video-v2005 rtl/perips/video.v rtl/perips/video_render.v rtl/utils/dpram.v rtl/utils/dpram2c.v
iverilog -g2005 -s vision -o /tmp/vision-v2005 rtl/vision/*.v rtl/utils/dpram.v rtl/utils/dpram2c.v
iverilog -g2005 -I . -s mes50hp_top -Pmes50hp_top.VIDEO_720P=0 -o /tmp/mes50hp-vga -f rtl/soc.f boards/mes50hp/mes50hp_top.v
```

三条均通过。最后一条改成 `VIDEO_720P=1` 时, 按预期报 `Unknown module type: MES50HP_720P_PLL_TODO`:
非 Verilator 路径不会把行为级时钟带进综合。

日志在 `build/full-test.log`、`build/test/`、`build/sim-720p.log`、`build/sim-vga.log`;
当前截图 `build/sim/video_demo-hdmi.png`, VGA 副本 `build/sim/video_demo-vga-hdmi.png`。
交互 GUI 未实际打开, 已验证相同接收模型、截图转换及无窗口仿真路径。

## 资源估计 (待 PDS 确认)

| 改动 | DRM18K 增量 | 其它 |
| --- | --- | --- |
| 输出行缓存、调色板改双时钟 | 预计 0 | 容量仍 8192 bit / 4096 bit; 核实双时钟宽深映射 |
| 输出扫描、同步和握手 | 0 | 增加计数器、配置快照及同步 FF; 无综合 LUT/FF 数值 |
| 74.25 MHz 时钟 | 0 | 目标 +1 PLL, 具体 IP/频偏待定 |
| 输入测量、动态裁剪、整帧结果提交 | 0 | 不存输入大图; 保留现有 box4/颜色运算 |
| 小窗两份缓冲、每份 10 个 2048x8 块 | +4 | 原 16 块 -> 预计 20 块; 目标全片 123.5/134, 余 10.5 块等效容量 |

以上预计净增 4 块 RAM, 不是综合结果。RAM 的端口模式、片选和小窗分块读 mux 都要看 PDS 最终报告,
并验收系统、输入像素、输出像素时钟的完整时序和 I/O 约束。

## 生成位流前需要补齐

- `boards/mes50hp/video_clock.vh`: 生成/接入 PGL50H 的 50 -> 74.25 MHz PLL, 核对复位/LOCK。
  现在只有仿真时钟, 720p 硬件分支故意不能展开。没有原语参数和合法频率范围, 没有声称硬件能精确得到目标频率;
  若只能取近似值, 记录频率、ppm 偏差和最终刷新率。
- 补齐生成时钟、跨域快照约束、输出数据/时钟的接口时序约束, 检查 CDC、RAM 推断和全部时钟 WNS。
- MS7210: 源码说“RGB888 输入, 自动识别分辨率”, 未改寄存器表。需要盘古原始例程或寄存器手册核对 720p;
  当前无法验证锁定、同步极性处理、输出沿与板级延迟。
- EDID (B2) 未做: 未独立核实完整 EDID/CTA 结构, 保留原表与校验和, 包括过高时钟模式。
  后续应只声明 <=74.25 MHz 模式、保留扩展块第 3 字节 0xC0、不声明 YCbCr,
  对两块分别重算校验和并用解码器核对全部时序; 本次不能宣称主机会自动选安全模式。
- 按要求没查 800x600 异常根因、没接 VS、没改 MS7200 状态 0->2 的补配置/失败重试逻辑。
  没加 100K 支持, 没动 model/、display-plan、hand-model 或 review。

## 拿到位流后的检查顺序

1. 先看 PLL 的实际频率、LOCK、RAM 用量、CDC 和全部时序报告, 确认使用的是补齐 IP 的 720p 设计。
   保留一份 `VIDEO_720P=0` 的 VGA 位流作对照; 两种模式是重新编译切换。
2. 不接 HDMI 输入先测输出: MS7210 初始化成功, 显示器报告 1280x720/60 Hz;
   检查正 HS/VS、1650x750 总时序、左右各 160 黑边、3x3 像素、满高 720、首行/末行和冷启动。
3. 再跑背景、滚动、透明精灵、64 同行精灵、移动小窗/关闭小窗, 连续多帧检查条纹、错行和颜色;
   读 `0x2000_0008/0x2000_000C`, 确认 STATUS 消隐翻转和 FRAME 每帧递增。
4. 下载 VGA 对照位流: 640x480、2x2、负同步、25 MHz (约 59.524 Hz), 再切回 720p 位流复测。
5. 接 Mac/Windows 输入, 手动选择像素时钟 <=74.25 MHz 的模式 (原 EDID 仍会提供过高模式):
   依次试 640x480 (若主机提供)、800x600、1280x720。
   读 `0x4000_5018` 和 `0x4000_501C` (C 结构 `VISION->INPUT_SIZE/INPUT_STATUS`),
   宽高必须等于实际有效尺寸, 支持位=1、稳定位=1; 这比桌面逻辑分辨率更可靠。
6. 用带中心十字/坐标和四边标记的图, 核对 ROI 起点分别为 (0,0)、(80,60)、(320,120),
   小窗始终 160x120, 红盒重心在其坐标范围内。1024x768@60 通常像素时钟 65 MHz,
   可以作为额外上板验证项, 本机未仿真该模式。
7. 连续切模式、热插拔、短暂断流、过小输入: 过渡期间 FRAME 不发布坏统计、小窗保持最后一份已验证画面;
   稳定后自动恢复。停止输入时旧结果会保留, 目前没有断流超时, 最后一帧需要下一 SOF 才能发布。
8. 若 800x600 仍异常, 先记录尺寸/状态、MS7200 锁定状态与 I2C 错误, 再抓 DE/PCLK/RGB、SOF/EOL 和消隐拍数;
   检查行消隐 <4096、场消隐 >4096, 以及输入采样沿/建立保持。不要把异常直接归因于裁剪或 GAP。
