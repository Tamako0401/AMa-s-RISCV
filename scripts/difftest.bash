#!/usr/bin/env bash
# 离线 difftest: 同一个固件分别在 RTL(iverilog) 和 spike 上跑, 逐条比对提交日志.
# 用法: scripts/difftest.bash [固件名, 默认 smoke]
#   固件名是 build/cpu/ 下由 scripts/test-cpu.py 编译出的程序: smoke alu boot memory extensions
#   SPIKE 环境变量指定打过补丁的 spike (见 docs/difftest.md), 默认用 PATH 里的 spike.
# 说明见 docs/difftest.md
set -euo pipefail
cd "$(dirname "$0")/.."

firmware=${1:-smoke}
spike=${SPIKE:-spike}

# 各固件用到的扩展, spike 必须一致, 否则会把这些指令当非法指令
case "$firmware" in
    extensions) isa=rv32im_zicsr_zicntr ;;
    memory)     isa=rv32i_zifencei ;;
    *)          isa=rv32i ;;
esac

if [[ ! -f "build/cpu/$firmware.elf" || ! -f build/cpu/cpu-0-0.vvp ]]; then
    echo "没有找到 build/cpu/$firmware.elf 或 cpu-0-0.vvp, 请先运行 python scripts/test-cpu.py"
    exit 1
fi

run_dir="build/difftest/$firmware-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run_dir"
echo "本次运行于 $run_dir"

vvp build/cpu/cpu-0-0.vvp \
    +rom="build/cpu/$firmware-rom.hex" \
    +ram="build/cpu/$firmware-ram.hex" \
    +commitlog="$run_dir/rtl.log" > "$run_dir/vvp.out" 2>&1 || true
n=$(wc -l < "$run_dir/rtl.log")
echo "RTL 提交了 $n 条指令"

# spike 不认测试台的结束信箱, 只能限制条数. --instructions 较小时遇到异常(如 ecall)
# 会提前结束, 所以给一个大上限, 再截取前 n 行.
# 去掉 spike 额外记录的访存(mem ...)和 CSR 写(c832_mscratch ...)
"$spike" --isa="$isa" --disable-dtb --pc=0 \
    -m0x0:0x10000,0x10000000:0x10000 \
    --log-commits --instructions=$((n + 100000)) "build/cpu/$firmware.elf" 2>&1 \
    | grep '^core' | head -n "$n" \
    | sed -e 's/ mem .*//' -e 's/ c[0-9]*_[a-z0-9]* .*//' > "$run_dir/spike.log" || true

if diff "$run_dir/rtl.log" "$run_dir/spike.log" > "$run_dir/diff.txt"; then
    echo "PASS: $firmware 的 $n 条指令与 spike 一致"
else
    echo "FAIL: $firmware 与 spike 不一致, 前几处差异('<' 是 RTL, '>' 是 spike):"
    head -n 20 "$run_dir/diff.txt"
    exit 1
fi
