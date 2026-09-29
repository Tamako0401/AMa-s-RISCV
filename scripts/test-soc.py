"""Build and run the SoC-level test: a program on real RTL memory.

Requires Python 3, clang, ld.lld, llvm-objcopy, iverilog, vvp.
Unlike scripts/test-cpu.py, this runs rtl/soc_top/soc_top.v, i.e. the real
rib + rom + ram RTL, so it exercises the interconnect end to end.
"""
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/soc'

ROM_BYTES = 65536          # 0x0000_0000, 与 rtl/soc_top/soc_top.v 的 u_rom 一致
ROM_DP = ROM_BYTES // 4


def run(*args):
    subprocess.run([shutil.which(str(args[0])) or str(args[0]),
                    *[str(a) for a in args[1:]]], cwd=ROOT, check=True)


def build_program(name, src):
    """汇编 -> ELF -> ROM 镜像(hex)。RAM 不需要镜像: soc_top 的 ram.v 没有初值。"""
    obj = BUILD / f'{name}.o'
    run('clang', '--target=riscv32-unknown-elf', '-march=rv32i', '-mabi=ilp32',
        '-O2', '-ffreestanding', '-fno-builtin', '-fno-stack-protector',
        '-msmall-data-limit=0', '-mno-relax', '-c', src, '-o', obj)
    elf = BUILD / f'{name}.elf'
    run('ld.lld', '-m', 'elf32lriscv', '--no-relax', '-T', 'tests/cpu/link.ld', obj, '-o', elf)
    rom_bin = BUILD / f'{name}.bin'
    run('llvm-objcopy', '-O', 'binary', '--only-section=.text', elf, rom_bin)
    rom = rom_bin.read_bytes()
    if len(rom) > ROM_BYTES:
        raise ValueError(f'{name}: .text exceeds ROM ({len(rom)} > {ROM_BYTES})')
    rom += b'\xa5' * (ROM_BYTES - len(rom))     # 未初始化部分填非法指令
    rom_hex = BUILD / f'{name}.rom.hex'
    rom_hex.write_text(''.join(f'{int.from_bytes(rom[i:i+4], "little"):08x}\n'
                               for i in range(0, ROM_BYTES, 4)), encoding='ascii')
    return rom_hex


def main():
    for tool in ['clang', 'ld.lld', 'llvm-objcopy', 'iverilog', 'vvp']:
        if not shutil.which(tool):
            raise SystemExit(f'Missing required tool: {tool}')
    BUILD.mkdir(parents=True, exist_ok=True)

    rom = build_program('soc_smoke', 'tests/soc/soc_smoke.S')

    vvp = BUILD / 'soc_tb.vvp'
    run('iverilog', '-g2012', '-s', 'soc_tb', '-o', vvp,
        '-f', 'rtl/soc.f', 'tests/soc/soc_tb.sv')
    run('vvp', vvp, f'+rom={rom.as_posix()}', '+stores=19')

    print('PASS: 1 SoC program run', flush=True)


if __name__ == '__main__':
    main()
