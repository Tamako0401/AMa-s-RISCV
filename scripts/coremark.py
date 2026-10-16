"""编译 CoreMark (sw/app/coremark + third_party/coremark) 并在 rtl/soc_top 上仿真。

用法: python3 scripts/coremark.py [--cc clang|gcc] [--iterations N] [--opt=-O2] [--min-score X]
上板构建: python3 scripts/build-board.py --harvard --app coremark [--pds]

CoreMark 的分数 = 迭代次数 / 秒。本 CPU 的计时单位是时钟周期, 所以
    CoreMark/MHz = 迭代次数 * 1e6 / Total ticks
与主频无关, 只看流水线效率。仿真和实机是同一份 RTL, 周期数相同, 所以仿真跑几次迭代
就能算准 CoreMark/MHz; CoreMark 规定的 "至少 10 秒" 只在实机上满足 (仿真跑不了那么久,
输出里会有一句 "ERROR! Must execute for at least 10 secs", 仿真时忽略即可)。
"""
import argparse
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/coremark'

SOURCES = ['sw/startup.S', 'sw/drivers/uart.c', 'sw/bsp/bsp.c',
           'sw/app/coremark/core_portme.c', 'sw/app/coremark/ee_printf.c',
           'third_party/coremark/core_list_join.c', 'third_party/coremark/core_main.c',
           'third_party/coremark/core_matrix.c', 'third_party/coremark/core_state.c',
           'third_party/coremark/core_util.c']
INCLUDES = ['sw/device', 'sw/drivers', 'sw/bsp', 'sw/app/coremark', 'third_party/coremark']
# 打开乘除法 (M 扩展): CPU 支持 (tests/cpu/extensions.S 验过), CoreMark 里乘法很多
MARCH = 'rv32im_zicsr'


def compiler(cc):
    if cc == 'clang':
        candidates = ['clang']
    else:
        candidates = ['riscv32-unknown-elf-gcc', 'riscv64-unknown-elf-gcc', 'riscv64-elf-gcc']
    for candidate in candidates:
        if path := shutil.which(candidate):
            return path
    raise SystemExit(f'找不到编译器: {", ".join(candidates)}')


def cflags(iterations, opt='-O2', cc='clang'):
    """CoreMark 的编译选项。FLAGS_STR 会原样打印在结果里 (CoreMark 要求报告编译选项)。"""
    perf = opt.split()
    target = ['--target=riscv32-unknown-elf', '-fuse-ld=lld'] if cc == 'clang' else []
    return [*target, f'-march={MARCH}', '-mabi=ilp32',
            *perf, '-nostdlib', '-ffreestanding', '-fno-builtin',
            '-msmall-data-limit=0', '-mno-relax',
            f'-DITERATIONS={iterations}', f'-DFLAGS_STR="{" ".join(perf)} -march={MARCH}"',
            *[f'-I{ROOT / i}' for i in INCLUDES], '-T', ROOT / 'sw/link.ld']


def run(*args, **kw):
    return subprocess.run([shutil.which(str(args[0])) or str(args[0]), *map(str, args[1:])],
                          cwd=ROOT, check=True, **kw)


def build(elf, iterations, opt='-O2', cc='clang'):
    libs = ['-lgcc'] if cc == 'gcc' else []
    run(compiler(cc), *cflags(iterations, opt, cc), *[ROOT / s for s in SOURCES],
        *libs, '-o', elf)


def score(output):
    """从 CoreMark 输出里算 CoreMark/MHz; 算法结果 (CRC) 不对时返回 None。

    CoreMark 自己把 "没跑满 10 秒" 也记作一个错误; 仿真跑不满, 所以这里只看
    CRC 和数据类型检查: 有 "ERROR!" 且不是那条 10 秒提示的, 就算失败。"""
    errors = [line for line in output.splitlines()
              if 'ERROR!' in line and 'at least 10 secs' not in line]
    it = re.search(r'Iterations\s*:\s*(\d+)', output)
    ticks = re.search(r'Total ticks\s*:\s*(\d+)', output)
    if errors or 'crcfinal' not in output or not it or not ticks:
        return None
    if int(it.group(1)) <= 0 or int(ticks.group(1)) <= 0:
        return None
    return int(it.group(1)) * 1e6 / int(ticks.group(1))


def append_summary(path, output, result):
    """追加本次仿真的结果, 同一文件只写一次表头。"""
    def field(name):
        match = re.search(rf'^{name}\s*:\s*([^\r\n]+)', output, re.MULTILINE)
        return match.group(1).strip().replace('|', '\\|') if match else '未知'

    with path.open('a', encoding='utf-8') as summary:
        if summary.tell() == 0:
            summary.write('| 编译器 | 选项 | CRC 是否通过 | CoreMark/MHz | 迭代次数 | Total ticks |\n'
                          '| --- | --- | --- | --- | --- | --- |\n')
        value = f'{result:.6f}' if result is not None else '—'
        crc = '通过' if result is not None else '失败'
        summary.write(f'| {field("Compiler version")} | {field("Compiler flags")} | {crc} | '
                      f'{value} | {field("Iterations")} | {field("Total ticks")} |\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--iterations', type=int, default=3, help='仿真迭代次数 (默认 3)')
    parser.add_argument('--opt', default='-O2', help='优化选项, 如 -O2 / -O3 / "-O3 -funroll-loops"')
    parser.add_argument('--cc', choices=['clang', 'gcc'], default='clang', help='编译器 (默认 clang)')
    parser.add_argument('--min-score', type=float, help='CoreMark/MHz 底线, 低于此值时失败')
    parser.add_argument('--summary', type=Path, help='追加 Markdown 表格到指定文件')
    args = parser.parse_args()
    if args.iterations <= 0:
        parser.error('--iterations 必须大于 0')
    if args.min_score is not None and (not math.isfinite(args.min_score) or args.min_score < 0):
        parser.error('--min-score 必须是非负有限数')
    BUILD.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(ROOT / 'scripts'))
    from elf2hex import elf_to_rom, write_hex

    elf = BUILD / 'coremark-sim.elf'
    build(elf, args.iterations, args.opt, args.cc)
    rom = BUILD / 'coremark-sim.hex'
    write_hex(elf_to_rom(elf), rom)

    objdir = BUILD / 'obj'
    run('verilator', '--binary', '--timing', '-Wno-fatal', '--top-module', 'coremark_tb',
        '-f', 'rtl/soc.f', 'tests/soc/coremark_tb.sv', '--Mdir', objdir, '-o', 'coremark_tb_sim',
        stdout=subprocess.DEVNULL)
    out = run(objdir / 'coremark_tb_sim', f'+rom={rom}', stdout=subprocess.PIPE, text=True).stdout
    print(out, end='')
    s = score(out)
    if args.summary:
        append_summary(args.summary, out, s)
    if s is None:
        raise SystemExit('FAIL coremark: CRC 校验没有通过, 见上面的 ERROR 行')
    if args.min_score is not None and s < args.min_score:
        raise SystemExit(f'FAIL coremark: 实际 {s:.6f} CoreMark/MHz, 低于底线 {args.min_score:.6f}')
    print(f'PASS coremark: CRC 校验通过, {s:.3f} CoreMark/MHz '
          f'(50 MHz 下约 {s * 50:.1f} CoreMark)')


if __name__ == '__main__':
    main()
