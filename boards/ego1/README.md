# EGO1 哈佛 SoC 上板工程

用于没有 MES50HP 时验证 UART 和 CoreMark; 比赛正式板仍为 MES50HP。
器件 `xc7a35tcsg324-1`, 直接例化 `boards/mes50hp/mes50hp_top_harvard.v`。
P17 的 100 MHz 经 MMCME2_BASE 和 BUFG 变为 50 MHz, 锁定前保持复位,
因此共用 `sw/` 固件、50 MHz BSP 和 115200 波特率。LCD 输出悬空。

## 构建

在仓库根目录执行:

```sh
python3 scripts/build-board.py --board ego1 --harvard
python3 scripts/build-board.py --board ego1 --harvard --vivado
python3 scripts/build-board.py --board ego1 --harvard --app coremark --vivado
```

依赖 Python 3、clang 的 RISC-V 后端、ld.lld 和 Vivado (本机为 2025.2)。
第一条只生成固件和非工程模式 `build.tcl`; 后两条运行综合、布局布线并生成位流。
只支持哈佛版和 CoreMark, 不支持 `--lcd`、`--pds`。
`--simulate` 沿用 MES50HP 的 50 MHz SoC 测试台, 不验证 MMCM 和 EGO1 引脚。

默认调用:

```sh
DBX_CONTAINER_MANAGER=docker distrobox enter vivado -- /tools/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source build.tcl
```

其他安装位置用 `VIVADO` 覆盖可执行文件或完整命令, 如
`VIVADO=/opt/Xilinx/Vivado/bin/vivado python3 scripts/build-board.py --board ego1 --harvard --vivado`。
脚本从输出目录启动 Vivado, Tcl 也切换到该目录, 以便 `$readmemh("firmware.hex")`
读到 ROM 初值。修改固件后必须重新综合生成位流。

输出分别在 `build/ego1-harvard/` 和 `build/ego1-harvard-coremark/`:

- `firmware.elf`、`firmware.hex`: ROM 镜像; RAM 不预装, startup.S 每次复位恢复 .data 并清 BSS。
- `ego1_top.bit`: SRAM 配置位流。
- `vivado-build.log`、`timing_summary.rpt`、`utilization.rpt`: 构建日志、布线后时序和资源。
- `build-manifest.json`: 成功构建的输入和产物 SHA-256。

脚本检查 ROM 初值成功读取、WNS >= 0 和位流生成, 失败即报错。
XDC 只定义实际使用的 IO 和 100 MHz 主时钟, 50 MHz 生成时钟由 Vivado 推导;
UART、按键和 LED 没有同步外部接口时序约束, WNS 用来验收内部时序。

2026-10-16 本机 Vivado 2025.2 实测 (布线后, RAMB36 单位为个):

| 固件 | WNS (ns) | LUT | FF | RAMB36 |
|---|---:|---:|---:|---:|
| board_check | +0.732 | 4157 | 2314 | 16 |
| coremark | +1.009 | 7477 | 2448 | 16 |

两版均生成位流并通过 ROM 初值检查。MES50HP 的 `--harvard --simulate` 和
`--harvard --lcd --simulate` 回归也通过。上述结果不代替实机验收。

## 下载与串口验收

1. USB 接 J6 (UART/JTAG), 打开电源。Vivado Hardware Manager → Open Target → Auto Connect,
   确认器件为 xc7a35t → Program Device, 选择对应目录的 `ego1_top.bit`。成功后 D24 亮;
   首轮只下载 SRAM, 断电后配置丢失。
2. 串口助手选择 FT2232 的 UART 口 (Linux 通常为 `/dev/ttyUSB1`, 以实际枚举为准),
   设置 **115200、8N1、无流控**, 关闭本地回显。先打开串口, 再按下并释放 **S6 (RST)**。
3. 默认程序应输出 `AMA CPU PASS`, LD2 的 8 个 LED 约每 0.5 秒移位一次,
   这是 CPU 执行 C 程序写 GPIO 的结果。`led[0..7]` 对应丝印 LD2-0..7, 高电平亮。
4. 发送单个 ASCII `Z`, 关闭自动追加换行, 应收到一个 `Z`; UART 没有 FIFO, 先不发大批数据。
5. 再按 S6, 应重新 PASS 和控灯; 程序会改掉有初值的变量, 复位恢复失败会报 `AMA CPU FAIL 2`。
   FAIL 2/3/4/5/6 分别对应初始化数据、BSS、RAM、栈/调用、字节/半字写。
   哈佛 SoC 访问未映射地址会一直等待, 没有总线故障灯。
6. CoreMark 位流改看 `Correct operation validated` 和 `Iterations/Sec`;
   自动选择运行至少 10 秒的迭代数, 初次试跑也需要时间。用 Iterations × 50000000 / Total ticks
   算精确 CoreMark, 除以 50 得 CoreMark/MHz。按 S6 后应重新运行并通过 CRC。

综合后同时核对资源报告: RAM 64 KiB 应有 BRAM, ROM 64 KiB 的填充区可能被优化,
不能要求它占满 64 KiB BRAM; 还需确认日志中 `firmware.hex` 读取成功。
无串口输出时先检查下载状态、串口及参数、S6 和时钟。

## S6 极性与待上板确认

依据课程资料 `EGo1用户手册.pdf` 第 2 页 §5.1 的原理图: FPGA_RESET 经 R28 (4.7 kΩ)
上拉到 3.3 V, S6 按下接地; 第 3 页表格将 FPGA_RESET 对应到 P15。
所以 S6 **松开为高、按下为低**。手册中“默认低、按下高”说的是 S0~S4, 不适用于 S6。
老师测试工程 (含 rar 内的 Verilog/XDC) 没有使用 P15, 无法提供额外极性证据。

顶层 `rst_n` 直接使用此低有效电平, 取反送入 MMCM 的高有效 RST,
并与 LOCKED 相与后送入 mes50hp_top 的 KEY1 低有效复位; 后者同步释放。
不要按 **S5 (PROG)** 代替 S6, S5 会清除 FPGA 配置。

待上板确认: 用万用表量 P15 的可接触测试点/连线对地电压, 应为松开约 3.3 V、按下约 0 V;
也可临时用只含 `assign led[0] = rst_n;` 的小顶层配合本 XDC 中 P15/K2 的约束,
应看到 LD2-0 松开亮、按下灭。若相反, 先核对板卡版本和原理图再修改复位极性。
尚未进行实机下载; 串口、LED、重复复位和 CoreMark 的实机验收均待完成。
