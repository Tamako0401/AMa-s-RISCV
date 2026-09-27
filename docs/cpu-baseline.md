# CPU 仿真基线

当前基线接入紫光版 RISC-V CPU 的完整流水线，顶层为 `tinyriscv_core`。模块位于 `rtl/core/`，由 `rtl/cpu.f` 统一列出，复用已有的 `exu_alu_datapath` 和 `gpr_reg`，不重复定义 ALU 或寄存器堆。

## 仿真范围

- 架构：RV32I，小端，复位地址 `0x80000000`
- 仿真 RAM：`0x80000000` 到 `0x8000ffff`，64 KiB
- 仿真存储器：`tests/cpu/cpu_tb.sv`，支持取指和数据请求延迟、背压及请求稳定性检查
- 程序：算术与分支、启动/BSS、访存、扩展指令
- 回归：`python scripts/test-cpu.py`，当前为 15 组程序/延迟配置

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