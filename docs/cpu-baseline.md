# CPU 仿真基线

当前基线接入紫光版 RISC-V CPU 的完整流水线，顶层为 `tinyriscv_core`。模块位于 `rtl/core/`，由 `rtl/cpu.f` 统一列出，复用已有的 `exu_alu_datapath` 和 `gpr_reg`，不重复定义 ALU 或寄存器堆。

## 仿真范围

- 架构：RV32I，小端，复位地址 `0x00000000`（哈佛式 ROM 基址）
- 指令存储器（ROM）：`0x00000000` 到 `0x0000ffff`，64 KiB；数据总线只能读，写被忽略
- 数据存储器（RAM）：`0x10000000` 到 `0x1000ffff`，64 KiB
- 映射与 `rtl/core/rib.v` 的从设备译码一致：ROM = s0，RAM = s1
- 结束约定：程序向 RAM 窗口第 0 个字 `0x10000000` 写 4 字节表示结束并上报返回值，
  因此 `tests/cpu/link.ld` 把可用 RAM 从 `0x10000004` 开始
- 仿真存储器：`tests/cpu/cpu_tb.sv`，两块独立的行为级存储模型，支持取指和数据请求延迟、
  背压及请求稳定性检查
- 程序：算术与分支、启动/BSS、访存（含"写 ROM 被忽略"）、扩展指令
- 回归：`python scripts/test-cpu.py`，当前为 15 组程序/延迟配置

## 已知环境问题

`rtl/core/exu_muldiv.v` 中 `div_ready` 在第 47 行被使用、第 50 行才声明，Icarus 13
在 `-g2012` 下会拒绝展开该模块（`Unable to bind wire/reg/memory`），因此本机目前
无法直接运行 `test-cpu.py`。把该声明移到使用之前即可，逻辑无需改动。

## 运行

需要 Python 3、clang、ld.lld、llvm-objcopy、iverilog 和 vvp：

```text
python scripts/test-cpu.py
```

快速 smoke 检查使用：

```text
python scripts/test-cpu.py --quick
```

这套基线只证明 RTL 仿真和软件小程序闭环，不证明 PANGO IP 映射、综合时序、位流生成或实机运行。