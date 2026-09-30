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
RAM_BYTES = 65536          # 0x1000_0000, 与 rtl/soc_top/soc_top.v 的 u_ram 一致
RESULT_RESERVE = 4         # RAM 窗口第 0 个字留给结果信箱, 见 tests/cpu/link.ld


def run(*args):
    subprocess.run([shutil.which(str(args[0])) or str(args[0]),
                    *[str(a) for a in args[1:]]], cwd=ROOT, check=True)


def build_program(name, src):
    """汇编 -> ELF -> ROM/RAM 两个 hex 镜像。"""
    obj = BUILD / f'{name}.o'
    run('clang', '--target=riscv32-unknown-elf', '-march=rv32i', '-mabi=ilp32',
        '-O2', '-ffreestanding', '-fno-builtin', '-fno-stack-protector',
        '-msmall-data-limit=0', '-mno-relax', '-c', src, '-o', obj)
    elf = BUILD / f'{name}.elf'
    run('ld.lld', '-m', 'elf32lriscv', '--no-relax', '-T', 'tests/cpu/link.ld', obj, '-o', elf)
    rom_bin = BUILD / f'{name}-rom.bin'
    ram_bin = BUILD / f'{name}-ram.bin'
    run('llvm-objcopy', '-O', 'binary', '--only-section=.text', elf, rom_bin)
    run('llvm-objcopy', '-O', 'binary', '--only-section=.data', elf, ram_bin)
    rom = rom_bin.read_bytes()
    if len(rom) > ROM_BYTES:
        raise ValueError(f'{name}: .text exceeds ROM ({len(rom)} > {ROM_BYTES})')
    rom += b'\xa5' * (ROM_BYTES - len(rom))     # 未初始化部分填非法指令
    # RAM 窗口第 0 个字留给结果信箱(与 link.ld 的 ORIGIN 对齐), 其后是 .data
    # 初值; 再往后填 0xa5, 便于发现"读到没写过的地方"。
    data = ram_bin.read_bytes()
    if len(data) > RAM_BYTES - RESULT_RESERVE:
        raise ValueError(f'{name}: .data exceeds RAM ({len(data)})')
    ram = b'\x00' * RESULT_RESERVE + data
    ram += b'\xa5' * (RAM_BYTES - len(ram))
    out = []
    for region, image in (('rom', rom), ('ram', ram)):
        path = BUILD / f'{name}.{region}.hex'
        path.write_text(''.join(f'{int.from_bytes(image[i:i+4], "little"):08x}\n'
                                for i in range(0, len(image), 4)), encoding='ascii')
        out.append(path)
    return out[0], out[1]


def main():
    for tool in ['clang', 'ld.lld', 'llvm-objcopy', 'iverilog', 'vvp']:
        if not shutil.which(tool):
            raise SystemExit(f'Missing required tool: {tool}')
    BUILD.mkdir(parents=True, exist_ok=True)

    programs = [('soc_smoke', build_program('soc_smoke', 'tests/soc/soc_smoke.S'), 19),
                ('soc_data', build_program('soc_data', 'tests/soc/soc_data.S'), 1),
                ('soc_spi', build_program('soc_spi', 'tests/soc/soc_spi.S'), 13)]

    vvp = BUILD / 'soc_tb.vvp'
    run('iverilog', '-g2012', '-s', 'soc_tb', '-o', vvp,
        '-f', 'rtl/soc.f', 'tests/soc/soc_tb.sv')
    for name, (rom_hex, ram_hex), stores in programs:
        run('vvp', vvp, f'+rom={rom_hex.as_posix()}', f'+ram={ram_hex.as_posix()}',
            f'+stores={stores}', *(['+check_spi'] if name == 'soc_spi' else []))

    print(f'PASS: {len(programs)} SoC program runs', flush=True)


if __name__ == '__main__':
    main()
