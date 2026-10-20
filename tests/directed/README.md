# 已知缺陷定向测试

| CHECK | 检查 | 当前预期 |
| --- | --- | --- |
| 1 | `response_hold_tb.sv`：ROM、RAM/gen_ram 接受读请求后撤销 valid、改变地址，检查背压期间响应数据保持到消费。已有 `memory_tb` 的背压检查未改变地址。 | FAIL：响应仍有效，数据却跟随新地址变化。 |
| 2 | `trap_stack_tb.sv` + `trap_stack.S`：真实 CPU 从 MIE=1、MPIE=0 执行 ECALL/MRET，检查入口/返回的 MIE、MPIE，并核对 mcause、mepc。使用独立存储模型隔离第 1 项。 | FAIL：入口和返回均为 MIE=0、MPIE=0，应分别为 0/1、1/1。 |
