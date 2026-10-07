# MES50HP 最小 CPU 上板工程

适用随板资料中的 **MES50HP / PGL50H-6IFBG484**，工具实测 PDS 2022.2-SP1-Lite。使用 50 MHz 时钟、片上 RAM、LED、板载 USB-UART 和 GMT024-8p10p-SPI 屏幕（ST7789V，240×320，只写）；不需要 DDR 或 ADDA。

该工程使用 `rtl/soc/minimal_soc.v` 的统一 RAM 布局，显式把 CPU 的 `RESET_PC` 设为 `0x80000000`。仓库通用 RIB SoC 和 CPU 回归使用 ROM/RAM 分离布局、默认入口 `0x00000000`；两套顶层、链接脚本和程序镜像应各自配套。

## 现成文件与实机验收

工程生成在仓库的 `build/mes50hp/build.pds`，SRAM 下载文件为 `build/mes50hp/generate_bitstream/mes50hp_top.sbit`。

1. 使用随板电源供电；USB 下载器连接 JTAG；电脑另接板载 USB-UART Type-C。JTAG 下载器和串口是两个用途不同的接口。
2. 在 PDS 打开上述 `.pds`。使用 Fabric Configuration 扫描 JTAG，确认识别器件与 PGL50H 匹配；选择上述 `.sbit` 执行 SRAM 配置。第一轮不需要烧写 Flash，断电会丢失此次 SRAM 配置。
3. 串口助手选择板载 CP2102 对应的 COM 口，设为 **115200、8 数据位、无校验、1 停止位、无流控**。先打开串口，再按下并释放 **KEY1**。
4. 应收到 `AMA CPU PASS`，随后 LED 输出图案约每 0.5 秒移动一位。这个图案由 CPU 执行 C 程序写 GPIO 产生，不是独立硬件计数器控制。
5. 关闭串口助手的本地回显，发送单个 ASCII `Z`（关闭自动追加换行）；应收到一个 `Z`。当前 UART 没有 FIFO，先不要测试连续大批量数据。
6. 再按 KEY1，应再次收到 PASS 并重新开始控灯。不要把板上的重新加载固件键当成 KEY1；重新加载键会影响 FPGA 配置本身。

尚未进行本板实机下载。这些是待用户实际观察的验收标准；综合成功或仿真 PASS 不代表上述实机结果已经发生。

故障显示：`AMA CPU FAIL 2/3/4/5/6` 分别表示初始化数据、BSS 清零、RAM 图案、栈/函数调用、字节/半字写校验失败。CPU 访问非法地址会锁存总线故障并停止核，LED 输出为 `0x80`，需 KEY1 复位。没有串口输出时先排查电源、下载成功状态、COM 口与参数、KEY1，而不是直接认定 CPU 坏了。

## 重新生成

在仓库根目录执行：

```text
python scripts/build-board.py --simulate --pds
```

依赖 Python 3、clang 的 RISC-V 后端、ld.lld、llvm-objcopy、iverilog/vvp；默认 PDS 位于 `C:/pango/PDS_2022.2-SP1-Lite/bin/pds_shell.exe`，其他安装路径用环境变量 `PDS_SHELL` 指定。

只生成固件/构建脚本：省略两个选项。只跑系统仿真：添加 `--simulate`。仿真使用独立 `sim.hex`，仅把软件 LED 间隔缩短到 100000 个 CPU 时钟，UART 仍按真实 50 MHz/115200 时序测试；用于下载的 `firmware.hex` 保持 25000000 周期间隔。

PDS 的进程工作目录必须为 `build/mes50hp`；启动后仅在 Tcl 里 `cd` 不能改变它已选定的工程目录和程序镜像查找位置。构建脚本已处理此问题。打开 `.pds` 时保留生成目录结构，修改固件后必须重新综合并生成位流，不能只重编 C 就下载旧位流。

本地首次错误工作目录生成物保存在 `build/mes50hp/invalid-first-run`，其中初始化镜像未加载，**不能用于下载**。这是诊断存档，不是交付工程。

## SPI 屏幕演示

```text
python scripts/build-board.py --lcd --simulate --pds
```

固件 `sw/board/lcd_main.c` 复用分层驱动（`sw/drivers`、`sw/bsp`、`sw/components/lcd`），画面与通用 SoC 的 `sw/app/lcd_demo` 相同：黑底、白边框、绿对角线、红/绿/蓝三个色块。初始化序列逐值对齐厂商例程 `GMT024-8p10p-SPI-ST7789.c`（VCOM/porch/gamma，INVOFF，SPI 模式 3），只把 COLMOD 写成同义的 `0x55`。背光固定点亮，未接 GPIO 调光。

板级仿真用 `tests/board/board_lcd_tb.sv`：st7789_model 直接从顶层引脚重建画面并逐像素核对。仿真镜像用 `-DSIM_CYCLE_DIV=1000` 缩短初始化延时；用于下载的 `firmware.hex` 保持真实延时。

实机验收标准（待观察）：下载位流并按 KEY1 后，屏幕显示上述画面，串口收到 `AMA LCD PASS`，随后 LED 继续移位。先接好屏幕再上电；核对 VCC 为 3.3 V。

## 平台接口

| 项目 | 约定 |
| --- | --- |
| CPU 时钟 | 板载 50 MHz，不使用 PLL |
| 复位/入口 | KEY1 低有效，异步拉低、16 拍同步释放；配置时初始化复位移位链；PC=`0x80000000` |
| RAM | `0x80000000`–`0x8000ffff`，64 KiB，单端口同步读、按字节写，初始化固件随位流配置 |
| 栈顶 | `0x80010000` |
| UART | `0x30000000`，偏移 0/4/8/C/10 为控制、状态、分频、TX、RX |
| GPIO | `0x40000000` 控制、`0x40000004` 数据、`0x40000008` BSRR；位 0/1/2 为 LCD CS_N/DC/RST_N，位 8–15 对应 LED1–8 |
| SPI | `0x40002000`，CR1/CR2/SR/DR 子集，寄存器语义见 [SPI 文档](../../docs/spi.md)；只接屏幕，MISO 固定接地 |
| CPU 扩展 | 软件使用 RV32I + cycle CSR；保留源核 M/CSR，不代表完整特权验证 |

SoC 数据访问优先于取指，统一串行处理事务并锁存目标与响应。UART/GPIO 的请求只脉冲一次、响应侧固定就绪，由 SoC 捕获读值再交给 CPU，满足第一批组件的接入限制。该板级版本不沿用仿真的 `0x10000000` 完成邮箱。

## 引脚依据

参考位置：`E:/2026FPGA创新设计竞赛紫光同创杯资料包/盘古50K开发板资料/盘古50K开发板`。

- `3_Hardware/MES50HP开发板硬件使用手册_1V1.pdf`：印刷页 9 的时钟表、26 的 UART 表、32–33 的 KEY/LED 表。
- `2_Demo/01_led_test.rar`、`02_key_led_test.rar`、`04_uart_test.rar`：核对 FDC、器件与复位极性。示例标注 PDS 2022.1。

| 顶层端口 | 管脚 | 说明 |
| --- | --- | --- |
| clk | P20 | 50 MHz |
| key1_n | K18 | KEY1，低有效 |
| uart_tx / uart_rx | R9 / R8 | FPGA 视角 TX/RX，板载 CP2102 |
| led[0:7] | B2 / A2 / B3 / A3 / C5 / A5 / F7 / F8 | LED1–8，按手册高电平亮 |
| lcd_sck / lcd_mosi | W8 / V7 | 屏幕 SCL / SDA |
| lcd_cs / lcd_dc | V9 / T8 | 屏幕 CS / AO |
| lcd_rst_n / lcd_bl | U8 / U9 | 屏幕 RESET / BL（背光固定点亮） |

屏幕管脚位置取自厂商例程 `6-实验例程Demo-基于盘古50K/8-ADDA+SPI显示实验/display_test.fdc`。屏幕排针从上到下 GND VCC SCL SDA RESET AO CS BL：VCC 接 3.3 V、GND 共地，其余六针对应上表。

以上 I/O 使用 LVCMOS33。没有复制整套厂商 HDL/IP；引脚事实及约束写法来自随板资料，SoC、顶层、固件与系统测试为本仓库新增。

## 验证记录（2026-09-29）

- Icarus 实际解码 TX 引脚，核对 `AMA CPU PASS\r\n`，注入 Z 并验证回显；确认 CPU GPIO 变为 2；配置时启动和 KEY1 复位后重启均通过。
- 自检包含初始化数据、BSS、64 个 RAM 字、字节/半字写、栈数组和函数返回；不是完整 ISA 或全 RAM 压力测试。
- PDS 编译、ADS 综合、器件映射、布局布线、时序分析、位流生成完成。0 个锁存器，64 KiB RAM 映射为 32 个 DRM。
- 器件映射报告：3298 LUT、2243 FF、4 APM、32 DRM。使用 50 MHz 约束，时序报告 `All Constraints Met`，慢角 setup slack **+1.780 ns**；估算 54.885 MHz 不是实测最高频率。
- 异步 KEY/UART 输入和没有外部同步采样时钟的 LED/UART 输出设了 false path；CPU 内部同步路径按 20 ns 检查。K18 的 share-pin 提示对应随板示例同一管脚，未改作其他接口。
- 实机 UART、LED 和下载结果仍待用户核对，未操作连接中的板卡，也未烧写 Flash。

2026-09-30 合入当前 CPU 核后，重新运行系统仿真，配置时启动和 KEY1 复位后的 UART、Z 回显、CPU 控灯均通过；重新完成 PDS 全流程，仍为 3298 LUT、2243 FF、4 APM、32 DRM，50 MHz 时序约束全部满足，慢角 setup slack 为 +1.780 ns。构建脚本生成的 `build-manifest.json` 记录对应源码、固件、位流及时序报告的 SHA256。实机结果仍待核对。

2026-10-01 更新仓库与知识库时，发现旧构建清单中的 `gpio.v`、`minimal_soc.v` 已与当前源码不同，因此基于 `cf94471` 重新执行 `python scripts/build-board.py --simulate --pds`。配置启动、KEY1 重启、UART PASS、Z 回显和 CPU 控灯仿真通过；PDS 全流程及位流生成通过，初始化镜像加载正常。当前映射为 **3318 LUT、2243 FF、4 APM、32 DRM**，50 MHz 约束全部满足，慢角 setup slack **+1.272 ns**；报告估算 **53.396 MHz**，不是实测最高频率。构建清单的 31 项源码、固件、位流及时序文件均逐项匹配。实机下载与观察仍未完成。

2026-10-02 接入 SPI 屏幕：SPI 外设接入 `minimal_soc`（`0x40002000`，DR/CR1 写背压 Stall 数据口），GPIO 位 0/1/2 控屏、LED 移到位 8–15，背光固定点亮；bring-up 仿真（LED 新映射）通过。`--lcd` 流程下板级 LCD 仿真 `board_lcd_tb` 从顶层引脚重建画面，边框/对角线/色块逐像素核对通过；通用 RIB SoC 的 `lcd_tb` 回归同样通过（初始化序列已对齐厂商 GMT024 例程）。`python scripts/build-board.py --lcd --pds` 全流程通过：固件 3140 字节，映射 **3415 LUT、2301 FF、4 APM、32 DRM**，50 MHz 约束全部满足，慢角 setup slack **+1.166 ns**（SPI 逻辑使余量略降）。位流为 `build/mes50hp/generate_bitstream/mes50hp_top.sbit`，对应 LCD 演示固件。实机屏幕验收待做。
