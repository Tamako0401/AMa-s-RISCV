# Difftest

同一个固件分别在 RTL(iverilog) 和 spike 上运行，逐条比对"PC、指令、写回的寄存器和值"，
第一处不一致就是出错的指令。目前是离线比对：两边各自跑完，再 diff 日志。

## 准备 spike

平台的 ROM 在 `0x0`，与 spike 固定在 `0x0` 的调试模块重叠，需要打补丁
`third_party/spike/debug-start.patch`（基于 riscv-isa-sim `5f2a1d48`）：

```text
git clone https://github.com/riscv-software-src/riscv-isa-sim && cd riscv-isa-sim
git checkout 5f2a1d48
git apply <本仓库>/third_party/spike/debug-start.patch
mkdir build && cd build && ../configure --prefix=$HOME/.local/spike && make -j && make install
```

补丁代价：spike 的调试模块（`-H`/OpenOCD）不可用，`-d` 交互调试不受影响。

## 运行

```text
python scripts/test-cpu.py                                   # 编译固件和 cpu-0-0.vvp
SPIKE=~/.local/spike/bin/spike scripts/difftest.bash boot
```

固件名：`smoke alu boot memory extensions`，默认 `smoke`。日志在 `build/difftest/` 下。

RTL 日志由 `tests/cpu/cpu_tb.sv` 在传入 `+commitlog=文件` 时输出，不传则不记录，不影响回归。
提交判定：EX 级未暂停，且指令不是 `0x00000000`（冲刷气泡）或 `0x00000013`（取指气泡）。

## 已知差异（不是 CPU 的 bug）

| 固件 | 现象 | 原因 |
|---|---|---|
| smoke, alu | 一致 | |
| boot | 结尾恢复 s0-s11 时 RTL 为 `x`，spike 为 0 | 寄存器堆无复位；main 保存/恢复了从未写过的寄存器 |
| memory | `0x12c` 处指令不同 | 程序故意写 ROM：RTL 忽略写入，spike 的内存全部可写 |
| extensions | `rdcycle` 值不同 | RTL 约 5 拍一条指令，spike 1 拍一条 |
| extensions | RTL 日志缺 `mret` | 执行 `mret` 那拍 clint 暂停了 EX，被提交判定过滤掉 |

另外：真正的 `nop` 与取指气泡编码相同，也会被跳过；store 的访存内容目前不比对。
