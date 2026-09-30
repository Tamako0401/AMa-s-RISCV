# CPU 仿真基线

当前基线接入紫光版 RISC-V CPU 的取指、译码、执行、寄存器写回和控制链路，顶层为 `tinyriscv_core`。模块位于 `rtl/core/`，由 `rtl/cpu.f` 统一列出，复用已有的 `exu_alu_datapath` 和 `gpr_reg`，不重复定义 ALU 或寄存器堆。

来源固定为 JerryYin777/FPGA_Competition-RISC-V_Processor-in-PGL22G 的 `00a3334d7c98f57a6d429a5e18910a7e2e88390b`。这是经过接口修正的功能基线，不是未经修改的上游性能基线，也不是本队已完成的自主 CPU。保留 IF/ID/EX 组织，但取指采用保守的单笔未完成事务和一个响应缓冲，会插入气泡；不能据此宣称每拍执行一条指令或性能提升。

## 仿真范围

- 软件基础目标：RV32I、小端、ilp32；保留来源核的 M、CSR 和 trap 路径。扩展测试单独指定编译选项，不改变 RV32I 主测试。
- 复位地址：顶层参数 `RESET_PC` 默认 `0x00000000`（哈佛式 ROM 基址），测试台显式传入 ROM 基址。
- 指令存储器（ROM）：`0x00000000` 到 `0x0000ffff`，64 KiB；数据总线只能读，写被忽略
- 数据存储器（RAM）：`0x10000000` 到 `0x1000ffff`，64 KiB
- 映射与 `rtl/core/rib.v` 的从设备译码一致：ROM = s0，RAM = s1
- 结束约定：程序向 RAM 窗口第 0 个字 `0x10000000` 写 4 字节表示结束并上报返回值，
  因此 `tests/cpu/link.ld` 把可用 RAM 从 `0x10000004` 开始
- 仿真存储器：`tests/cpu/cpu_tb.sv`，两块独立的行为级存储模型，支持取指和数据请求延迟、
  背压及请求稳定性检查
- 程序：算术与分支、启动/BSS、访存（含"写 ROM 被忽略"）、扩展指令
- 回归：`python scripts/test-cpu.py`，当前为 15 组程序/延迟配置
- 栈顶：`0x10010000`；测试链接脚本为 `tests/cpu/link.ld`。
- 测试台完成邮箱写 1 通过，其他数为失败阶段号；这是测试保留区，不是硬件外设。
- CPU 回归的中断输入固定为 0，JTAG halt 固定为 0，使用行为级 ROM/RAM；`scripts/test-soc.py` 另行验证 RIB、真实 ROM/RAM RTL 和 SPI 寄存器通路。

## 接口约定

两个总线口均使用同一个 `clk` 和低有效复位 `rst_n`。地址为字节地址，数据为 32 位；`sel[3:0]` 表示四个字节通道。外部返回包含目标字节的对齐 32 位读数据，核内完成 lane 选择及符号扩展。

- 请求在 `req_valid && req_ready` 的上升沿接受；等待期间 valid、地址、写数据和字节使能保持稳定。
- 每个口最多一笔未完成事务。外部必须为读和写各返回一次响应，不得对同一请求重复执行写入。
- 响应可以任意延后；**不支持在请求接受的同一个周期消费组合响应**。零等待外设应加至少一级响应寄存器，或保持响应到核的 `rsp_ready` 有效。
- 响应在 `rsp_valid && rsp_ready` 的上升沿消费；等待期间外部须保持响应和数据，消费后可立即失效。
- 分支冲刷时，已发出的取指请求会继续完成，但其响应被丢弃。不会把错误路径响应交给译码。
- 系统复位必须同时清理 CPU 与外部未完成事务。该接口没有事务 ID、错误返回、突发和多时钟域支持，不能直接等同 AXI。

## 为接入所做的修正

| 文件 | 修正 |
| --- | --- |
| `ifu.v` | 替换依赖旧总线切换/固定时序的取指逻辑，锁存请求 PC、响应和冲刷状态；驱动原先未赋值的 `inst_valid_o` |
| `ifu_idu.v` | 无有效指令时插入 NOP，冲刷优先 |
| `exu_mem.v` | 每条访存指令只发一次请求；在请求阶段给出写使能；锁存读响应直到写回，不再依赖响应后数据仍有效；非对齐请求不发往外部 |
| `tinyriscv_core.v` | 参数化复位 PC；JAL/JALR 返回地址和 FENCE 后继地址使用执行中指令的 PC+4，而非译码级当前地址 |
| `exu.v` | JALR 目标地址清除 bit 0 |
| `exu_muldiv.v` | 将 `div_ready` 声明移到首次引用之前，兼容 ModelSim 10.5b 的 SystemVerilog 编译 |

其余新引入文件保留原逻辑，仅做编码、行尾和来源标记整理。原始及当前文件校验值、修改清单见 `third_party/tinyriscv-manifest.json`。

## 运行

需要 Python 3、支持 RISC-V 目标的 clang、ld.lld、llvm-objcopy、iverilog 和 vvp，均须位于 PATH：

```text
nu --no-config-file scripts/test-cpu.nu
```

快速 smoke 检查使用：

```text
nu --no-config-file scripts/test-cpu.nu --quick
```

`--vcd` 会为每组测试生成波形。直接使用 Python 入口也支持相同参数；Nu 入口可从任意目录运行。生成物均在已忽略的 `build/cpu/`，不依赖 `build/research/` 或本机参考仓库。

使用 ModelSim（额外需要 vlib/vmap/vlog/vsim）：

```text
nu --no-config-file scripts/test-cpu.nu --modelsim
```

ModelSim 在 `build/cpu/modelsim/` 创建独立库、配置及每组 Transcript，不修改安装目录的库映射。失败、超时或未到达完成标志均返回非零退出码。可组合 `--modelsim --quick --vcd` 先验证最小程序。

本次开发用 LLVM 生成 RV32 ELF，不依赖标准 C 库。这不替代赛题要求的 GCC 工具链和不少于 10 秒的 CoreMark 测量。

## 验证记录（2026-09-28）

2026-09-28 使用统一 RAM 布局时，Icarus 和本机 ModelSim Intel FPGA Starter 10.5b 均完成以下 5 个程序 × 3 组存储时序，共各 15 次运行。2026-09-30 合入远端的 ROM/RAM 分离布局后，两种模拟器均复跑 15/15 通过；保留远端提交日志功能，并给测试台补上 `defines.v` 引用，避免 ModelSim 按文件编译时找不到 `STALL_EX` 宏。当前地址约定见上文。

| 程序 | 检查内容 |
| --- | --- |
| `smoke.S` | 算术依赖、循环、JAL/返回、奇地址 JALR、load-use、错误路径 store 被冲刷、x0、FENCE；要求恰好 3 次 RAM 写 |
| 生成的 `alu.S` | 固定种子，320 组寄存器 ALU、144 组立即数运算及 30 组分支条件；期望值由 Python 整数运算生成 |
| `start.S` + `boot.c` | C 启动、已初始化数据、BSS 清零、栈数组、函数调用与累计校验；未加载 RAM 填入 A5 而非预先清零；启动代码初始化 callee-saved 寄存器，避免保存上电未定义值 |
| `memory.S` | 字节 lane、半字、符号扩展、负偏移、FENCE.I，以及写 ROM 被忽略；当前要求恰好 8 次 RAM 写，旧统一 RAM 版本为 9 次 |
| `extensions.S` | 八类 M 运算基本样例、除零/有符号溢出、六类 CSR 指令、cycle、ECALL/EBREAK 的 cause/PC 以及 MRET |

三组分别为固定响应时序、随机请求等待与额外 0–4/0–7 拍指令/数据延迟、额外 0–11/0–13 拍延迟。参数为等待计数上限，不是整个事务的总时延。测试台独立检查请求稳定性、地址范围、写次数、失败码和超时，并在响应消费后把数据置 X，防止核错误依赖旧读值。

额外检查有效请求及非 x0 寄存器写回中的未知值。2026-09-30 用 `+stores=4` 故意让 smoke 的写次数不匹配，Icarus 和 ModelSim 均因实际 3 次写入而返回退出码 1，验证批处理不会把仿真失败当作成功。

## 尚未证明的范围

- 这些是本地定向/确定性随机回归，不是完整 RISC-V 架构认证或穷举验证。没有进行官方 ISA suite、CoreMark、综合时序或实机验证。
- 继承的 CSR/异常模块只做了基本路径测试；异步中断、嵌套异常、非法指令、访问错误、特权规范及非对齐异常的完整语义仍需单独完善。不要宣称完整特权架构支持。
- 当前只验证对齐访存。来源 CLINT 对 load/store 非对齐使用相同 cause 等行为尚未整改，不能用本次阻止非法总线写入代替完整异常验证。
- `jtag_halt_i` 只限制取指；不是完整调试暂停协议。暂时接 0。
- 仿真存储器不是 PANGO BRAM/DDR IP。后续必须按已购 PGL50H 板卡重新生成/接入存储和时钟复位工程。
- `rtl/cpu.f` 与 `rtl/reusable.f` 有共同文件，创建 SoC 文件清单时应去重，不要把两份直接叠加编译。
