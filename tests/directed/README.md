# 已知缺陷定向测试

在仓库根目录运行：

```sh
python3 scripts/test-directed.py
```

依赖 Python 3、clang（RISC-V target）、ld.lld、llvm-objcopy、iverilog、vvp。
编译产物放在临时目录并自动清理；单项失败后继续运行其余项。
退出码：全部 PASS 为 0，功能 FAIL 为 1，工具或编译等 ERROR 为 2。
以下三项目前均为已知缺陷，预期 FAIL；修复后应 PASS，不接入 CI。

| CHECK | 检查 | 当前预期 |
| --- | --- | --- |
| 1 | `response_hold_tb.sv`：ROM、RAM/gen_ram 接受读请求后撤销 valid、改变地址，检查背压期间响应数据保持到消费。已有 `memory_tb` 的背压检查未改变地址。 | FAIL：响应仍有效，数据却跟随新地址变化。 |
| 2 | `trap_stack_tb.sv` + `trap_stack.S`：真实 CPU 从 MIE=1、MPIE=0 执行 ECALL/MRET，检查入口/返回的 MIE、MPIE，并核对 mcause、mepc。使用独立存储模型隔离第 1 项。 | FAIL：入口和返回均为 MIE=0、MPIE=0，应分别为 0/1、1/1。 |
| 3 | `board_reset_tb.sv` + `board_reset.c`：真实 `mes50hp_top` / `minimal_soc` 用原有 `sw/board/start.S`、`link.ld`，将全局变量从 3 改为 1 后按 KEY1，检查重启后恢复为 3。已有 `reset_tb` 测的是另一条 `soc_top` 启动路径。 | FAIL：重启仍读到 1；需恢复 `.data` 初值，无需复位时清空物理 RAM。 |

Icarus 13 仍无法编译 `minimal_soc.v` 中先使用后声明的 `spi_hit`。
脚本只在临时副本中前移该声明及其连续赋值，不改仓库 RTL。
