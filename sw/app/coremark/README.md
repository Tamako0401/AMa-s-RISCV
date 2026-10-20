# coremark: CoreMark 跑分

赛题指定的性能基准 (CoreMark v1.0)。算法文件在 `third_party/coremark/`, **一字不改** (CoreMark 规则,
CI 用 `third_party/coremark/SHA256SUMS` 核对); 这里只有移植层。

## 上板

```
ama run coremark
```

串口打印官方格式的结果, 最后一行 `[result] CoreMark/MHz x.xxx`。`ITERATIONS` 默认 0: CoreMark 自己定迭代次数,
保证运行超过 10 秒 (赛题要求)。

## 文件

| 文件 | 内容 |
| --- | --- |
| `app.toml` | 额外的源文件 (third_party/coremark 的算法)、编译选项 `-march=rv32im_zicsr` (CPU 支持乘除法) |
| `core_portme.c` | 计时: 用 `cycle` 计数器, 1 tick = 1 时钟周期; 跑完算 CoreMark/MHz (千分位) 打印 |
| `core_portme.h` | 类型、配置; `ITERATIONS` 默认 0 |
| `ee_printf.c` | 官方的 printf, 输出到串口 |

## 测试

`tests/soc/coremark_tb.sv` (`ama test tests/soc/coremark_tb.sv`): 仿真里跑 3 次迭代
(`-DITERATIONS=3`), 检查 CRC; 分数低于 `-DMIN_SCORE` (千分位, 现为 650 即 0.650) 算失败。
分数显示在 PASS 那一行后面。仿真的分数只看流水线和存储时序, 和上板时同一频率下的结果应该一致。

## 注意

- 分数和编译器版本有关 (同一份代码: 本机 gcc 16 为 0.716, CI 的 Ubuntu gcc 为 0.660)。交比赛结果前用
  `ama doctor` 记下编译器版本。
