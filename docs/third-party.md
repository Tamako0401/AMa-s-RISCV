# 可复用 RTL 移植清单

## 来源和授权

- 仓库：https://github.com/JerryYin777/FPGA_Competition-RISC-V_Processor-in-PGL22G
- 分支：`main`；固定提交：`00a3334d7c98f57a6d429a5e18910a7e2e88390b`。
- 导入日期：2026-09-25。
- 导入的八个源文件均有 Blue Liang 的版权及 Apache-2.0 文件头；当前保留其中七个，旧 GPIO 已删除。
- 许可证全文：`LICENSES/Apache-2.0.txt`，来自 https://www.apache.org/licenses/LICENSE-2.0.txt 。该许可证适用于本次导入的文件，不代表本仓库所有代码统一采用此许可证。
- 在该参考提交的文件树中未找到单独 LICENSE/NOTICE/COPYING 文件；不自行虚构上游 NOTICE。来源及修改记录保存在本文和 `third_party/tinyriscv-manifest.json`。
- 清单记录每个源文件的原始 SHA-256、导入后 SHA-256 和修改说明。导入后哈希是本次快照，后续自行改造会改变它。

## 已导入文件

| 上游路径 | 本地路径 | 依赖与改动 |
| --- | --- | --- |
| `source/utils/gen_dff.v` | `rtl/utils/gen_dff.v` | 六种寄存器模块；无逻辑改动 |
| `source/utils/gen_buf.v` | `rtl/utils/gen_buf.v` | `gen_ticks_sync`，依赖 `gen_dff.v`；无逻辑改动 |
| `source/utils/vld_rdy.v` | `rtl/utils/vld_rdy.v` | valid/ready 控制，依赖 `gen_dff.v`；无逻辑改动 |
| `source/utils/gen_ram.v` | `rtl/utils/gen_ram.v` | 通用 RTL RAM；删除未使用的 `defines.v` 引用；增加可选 `INIT_FILE` 初值参数 |
| `source/core/gpr_reg.v` | `rtl/core/gpr_reg.v` | 32 个通用寄存器，依赖 `gen_dff.v`；删除未使用的 `defines.v` 引用 |
| `source/core/exu_alu_datapath.v` | `rtl/core/exu_alu_datapath.v` | 运算/比较数据通路；删除未使用的 `defines.v` 引用 |
| `source/perips/uart.v` | `rtl/perips/uart.v` | UART 寄存器、TX/RX；移除 `defines.v`，将时钟宏改为 `CPU_CLOCK_HZ` 模块参数，默认仍为 50000000；请求握手门控及响应背压保持（不再使用 `vld_rdy.v`） |

## 接入条件

### UART

UART 寄存器和收发行为保留上游。只在请求握手那一拍执行读写，读响应保持到 `rsp_ready_i`，未取走响应时不接受新请求，因此可以挂在 rib 等会暂停响应消费的总线上。`tests/reusable/peripherals_tb.sv` 覆盖了响应背压下读数据保持、被阻塞的写不提前执行且只执行一次。

原 SPI 文件的版权/许可证头保留，不将它冒记为上表固定参考提交的来源文件。

| 外设 | 字节偏移 | 含义 |
| --- | --- | --- |
| UART | `0x00` | 控制：bit0 TX 使能、bit1 RX 使能 |
| UART | `0x04` | 状态：bit0 TX busy、bit1 RX 完成；向 bit1 写 0 清除完成标记 |
| UART | `0x08` | 分频寄存器，低 16 位有效 |
| UART | `0x0c` | TX 数据低 8 位；忙时不接受新发送；上游没有实现此地址的读回 |
| UART | `0x10` | RX 数据低 8 位 |

外设只解码低位偏移，上层必须做基地址和地址合法性检查。UART 接收有 16 字节 FIFO (本仓库加的, 满了丢新字节)，不支持流控、奇偶校验或完整错误检测，软件应及时读取。

UART 时钟参数只影响复位时的默认分频值；必须传入真实外设时钟。保留上游计数方式，单个 TX bit 持续 `分频值 + 1` 个时钟，不把 `CPU_CLOCK_HZ / 115200` 宣称为零误差波特率。本次数字仿真不证明异步输入的亚稳态可靠性。

### ALU、寄存器堆与工具模块

- `exu_alu_datapath` 的 ALU/BJP/MEM/CSR 请求互斥；它不负责指令译码、分支冲刷或 JALR 地址对齐。CSR 输入需按原接口预处理，例如清位操作送入反相后的掩码。
- `gpr_reg` 保持 x0 为零，支持同拍写地址的组合旁路；x1–x31 **不随复位清零**，未写过的值不可假设为零。`rst_n` 虽在接口中，但不清除寄存器内容。
- `gen_ram` 使用**字地址**，采样读地址后输出对应内容，按字节写；未初始化的存储单元未知。可选的 `INIT_FILE` 参数用 `$readmemh` 载入初值（文件名为空则不初始化）：该方式已在仿真中验证，并由 `rtl/perips/ram.v` 的 `RAM_INIT_FILE` 与 `tests/reusable/memory_tb.sv`、`tests/soc/` 覆盖。调用方保证地址在范围内及参数合法。
- `gen_pipe_dff` 的 `hold_en` 实际使输出装载 `def_val`，不是保留旧值。设计新流水时不要误解其名称。
- `gen_ticks_sync` 是寄存器延迟链。多位数据跨时钟域不能仅靠它保证一致性；本次没有导入完整 CDC 事务模块。

## 上游暂缓部分与后续接入状态

| 部分 | 原因与后续工作 |
| --- | --- |
| `perips/timer.v` | 代码中 `timer_ctrl[2]` 没有置 pending 的路径，注释与实际状态不一致；中断清除条件也没有同时检查字节使能。先修正并测试寄存器语义再移植，不能直接当可信计时模块 |
| CPU 译码/流水寄存器/控制/执行组织 | 已按完整 CPU 基线接入 `rtl/core/`；SoC 与板级工程的验证范围分别记录 |
| CSR、中断、乘除 | 已随 CPU 核导入；乘除和 CSR/同步 trap 基本路径已测，异步中断与完整异常语义尚未验证，见 `cpu-baseline.md` |
| JTAG 与 CDC 事务模块 | 暂不导入，需确定调试/复位及跨域约定后验证 |
