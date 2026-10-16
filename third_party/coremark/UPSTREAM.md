# CoreMark (EEMBC) 原样拷贝

- 来源: https://github.com/eembc/coremark
- 提交: 1f483d5b8316753a742cbf5590caf5bd0a4e4777 (2025-05-01)
- 拷贝的文件: core_list_join.c core_main.c core_matrix.c core_state.c core_util.c coremark.h LICENSE.md README.md, 一字未改。

CoreMark 的规则 (见 README.md "Run and Reporting Rules"): 只允许改移植层
(core_portme.c / core_portme.h / ee_printf.c), 算法文件不能动, 否则结果不算 CoreMark。
本仓库的移植层在 sw/app/coremark/, 构建和仿真见 scripts/coremark.py。
