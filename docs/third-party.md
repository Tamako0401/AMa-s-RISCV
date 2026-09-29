# 可复用 RTL 移植清单

本批次把不依赖紫光器件原语的组件和完整 CPU 基线移入 `rtl/`，提供独立编译清单和自检仿真。**CPU 仿真基线已跑通，但不代表 SoC、PDS 或远程板卡工程已跑通。**未更改现有 `sw/`、`experiments/`、`docs/platform.md` 和软件构建配置；未确定新的系统地址映射。

## 来源和授权

- 仓库：https://github.com/JerryYin777/FPGA_Competition-RISC-V_Processor-in-PGL22G
- 分支：`main`；固定提交：`00a3334d7c98f57a6d429a5e18910a7e2e88390b`。
- 导入日期：2026-09-25。
- 八个源文件均有 Blue Liang 的版权及 Apache-2.0 文件头，已保留。
- 许可证全文：`LICENSES/Apache-2.0.txt`，来自 https://www.apache.org/licenses/LICENSE-2.0.txt 。该许可证适用于本次导入的文件，不代表本仓库所有代码统一采用此许可证。
- 在该参考提交的文件树中未找到单独 LICENSE/NOTICE/COPYING 文件；不自行虚构上游 NOTICE。来源及修改记录保存在本文和 `third_party/tinyriscv-manifest.json`。
- 清单记录每个源文件的原始 SHA-256、导入后 SHA-256 和修改说明。导入后哈希是本次快照，后续自行改造会改变它。

## 已导入文件

除下表所述改动外，保持原 RTL 逻辑。所有文件统一 LF、去除行尾空白，并增加来源/修改说明；没有重命名模块或删除版权。

| 上游路径 | 本地路径 | 依赖与改动 |
| --- | --- | --- |
| `source/utils/gen_dff.v` | `rtl/utils/gen_dff.v` | 六种寄存器模块；无逻辑改动 |
| `source/utils/gen_buf.v` | `rtl/utils/gen_buf.v` | `gen_ticks_sync`，依赖 `gen_dff.v`；无逻辑改动 |
| `source/utils/vld_rdy.v` | `rtl/utils/vld_rdy.v` | valid/ready 控制，依赖 `gen_dff.v`；无逻辑改动 |
| `source/utils/gen_ram.v` | `rtl/utils/gen_ram.v` | 通用 RTL RAM；删除未使用的 `defines.v` 引用；增加可选 `INIT_FILE` 初值参数 |
| `source/core/gpr_reg.v` | `rtl/core/gpr_reg.v` | 32 个通用寄存器，依赖 `gen_dff.v`；删除未使用的 `defines.v` 引用 |
| `source/core/exu_alu_datapath.v` | `rtl/core/exu_alu_datapath.v` | 运算/比较数据通路；删除未使用的 `defines.v` 引用 |
| `source/perips/gpio.v` | `rtl/perips/gpio.v` | GPIO 寄存器和输入采样，依赖 `vld_rdy.v`；无逻辑改动 |
| `source/perips/uart.v` | `rtl/perips/uart.v` | UART 寄存器、TX/RX，依赖 `vld_rdy.v`；移除 `defines.v`，将时钟宏改为 `CPU_CLOCK_HZ` 模块参数，默认仍为 50000000 |

不导入旧 `defines.v`，避免把复位地址、流水级数、旧 CPU 频率等全局配置带入当前平台。

## 接入条件

### GPIO 与 UART

这两个外设保留了上游接口和行为，**本批次仅支持响应端始终就绪的使用方式**：`rsp_ready_i = 1`，一次请求在时钟沿被接受后撤销，不能为“等待响应”而将同一次写请求反复保持多个时钟。读响应在请求后的寄存器输出上取得，按 `rsp_valid_o` 消费。

原因是上游 `data_r` 没有独立的背压保持逻辑，且写使能只由 `we_i & req_valid_i` 决定，不包含 `req_ready_o`。若未来 CPU/总线可能暂停响应消费，必须增加事务适配/缓冲并做回归；不能把它们直接当成任意 ready/valid 总线从设备。`vld_rdy` 本身只保存 valid，不保存 payload。

| 外设 | 字节偏移 | 含义 |
| --- | --- | --- |
| GPIO | `0x00` | 控制：每两位控制一个引脚，1 输出、2 输入、0 高阻语义 |
| GPIO | `0x04` | 数据：当前模块仅有两个输入引脚，数据写入支持低两个字节 |
| UART | `0x00` | 控制：bit0 TX 使能、bit1 RX 使能 |
| UART | `0x04` | 状态：bit0 TX busy、bit1 RX 完成；向 bit1 写 0 清除完成标记 |
| UART | `0x08` | 分频寄存器，低 16 位有效 |
| UART | `0x0c` | TX 数据低 8 位；忙时不接受新发送；上游没有实现此地址的读回 |
| UART | `0x10` | RX 数据低 8 位 |

外设只解码低位偏移，上层必须做基地址和地址合法性检查。GPIO 不包含物理三态缓冲，顶层负责根据模式连接实际引脚；异步 GPIO 输入的同步处理也留给顶层。UART 无 FIFO，不支持流控、奇偶校验或完整错误检测，软件应及时读取。

UART 时钟参数只影响复位时的默认分频值；必须传入真实外设时钟。保留上游计数方式，单个 TX bit 持续 `分频值 + 1` 个时钟，不把 `CPU_CLOCK_HZ / 115200` 宣称为零误差波特率。TX 在复位期间为低，复位释放后空闲状态变高；这是保留的上游行为。本次数字仿真不证明异步输入的亚稳态可靠性。

### ALU、寄存器堆与工具模块

- `exu_alu_datapath` 的 ALU/BJP/MEM/CSR 请求互斥；它不负责指令译码、分支冲刷或 JALR 地址对齐。CSR 输入需按原接口预处理，例如清位操作送入反相后的掩码。
- `gpr_reg` 保持 x0 为零，支持同拍写地址的组合旁路；x1–x31 **不随复位清零**，未写过的值不可假设为零。`rst_n` 虽在接口中，但不清除寄存器内容。
- `gen_ram` 使用**字地址**，采样读地址后输出对应内容，按字节写；未初始化的存储单元未知。可选的 `INIT_FILE` 参数用 `$readmemh` 载入初值（文件名为空则不初始化）：该方式已在仿真中验证，并由 `rtl/perips/ram.v` 的 `RAM_INIT_FILE` 与 `tests/reusable/memory_tb.sv`、`tests/soc/` 覆盖；但能否被综合工具推断成存储初值尚未验证。调用方保证地址在范围内及参数合法。本次没有证明它在 PDS 中会映射成哪种存储资源，不能把它当成已验证的紫光 BRAM IP 替代品。
- `gen_pipe_dff` 的 `hold_en` 实际使输出装载 `def_val`，不是保留旧值。设计新流水时不要误解其名称。
- `gen_ticks_sync` 是寄存器延迟链。多位数据跨时钟域不能仅靠它保证一致性；本次没有导入完整 CDC 事务模块。

## 本批次暂缓的部分

| 部分 | 原因与后续工作 |
| --- | --- |
| `sys_bus/rib.v` | 响应路由依赖当前主设备请求仲裁和当前地址，未独立锁存事务归属；需结合新 CPU 的请求保持方式、响应延迟和竞争测试后决定是否复用 |
| `perips/timer.v` | 代码中 `timer_ctrl[2]` 没有置 pending 的路径，注释与实际状态不一致；中断清除条件也没有同时检查字节使能。先修正并测试寄存器语义再移植，不能直接当可信计时模块 |
| `perips/ram.v`、`rom.v`、`ipcore/*` | 包装依赖 PANGO IP；目标器件、容量、读写时序及 IP 使用条款尚未对齐 |
| CPU 译码/流水寄存器/控制/执行组织 | 已按完整 CPU 基线接入 `rtl/core/`；后续 SoC/板级适配仍需单独验证 |
| CSR、中断、乘除、JTAG 与 CDC 事务模块 | 当前无接入消费者，需确定 ISA/调试/复位及跨域约定后连同相关路径验证 |
| SoC 顶层、PDS、FDC、PLL、位流及旧报告 | 板卡相关，远程设备尚未核实；旧成果不属于本队验证结果 |

## 验证和复现

在仓库根目录用 Nushell 执行 `nu --no-config-file scripts/test-reusable.nu`（若 nu 不在 PATH，使用已安装的 nu.exe 完整路径）。脚本也支持从其他工作目录启动，需要 `iverilog` 和 `vvp` 在 PATH。

`rtl/reusable.f` 是从仓库根目录解析的正式 RTL 文件清单，不包含测试台和器件 IP。生成物在已忽略的 `build/reusable/`。

2026-09-25 本机 Icarus 验证结果：

- 全部导入 RTL 使用 `-g2012 -Wall -t null` 编译/展开通过，无 RTL 警告。
- `storage_tb`：通过 x0/所有寄存器写读/同拍旁路/无复位保持、16 个 RAM 地址读写与字节掩码、同步读地址、两种 CUT_READY 的填充/背压/排空、同步链和寄存器默认值检查。
- `alu_tb`：通过 2560 组算术/逻辑/移位比较向量，另检查六类分支比较、跳转目标、访存地址和 CSR 数据通路示例。
- `peripherals_tb`：通过 GPIO 字节写与输入采样、UART 时钟参数、TX 独立解码、RX 外部注入以及状态清除。

这些是组件级回归，不是穷举证明、ISA 测试、PDS 综合/时序或实机验证。UART 测试使用加速分频，不代表已测真实板上 115200 波特率。后续 CPU/总线接入仍需系统级测试。

2026-09-26 复跑上述三组 Icarus 测试，均通过。用户提供的 ModelSim 截图中，`peripherals_tb` 在 3916 ns 输出 PASS；该截图证明外设测试通过，不代替其余测试或上板验证。用户核对后确认本次移植可以提交。

本批按“基础 RTL 与来源记录 → GPIO/UART → 测试与接入文档”组织提交。Agent 上下文 `prompt.md` 属于此前独立文档工作，不纳入本批移植提交。
