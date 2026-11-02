#!/usr/bin/env python3
"""只构建 CPU RTL, 对比同一320弹场景的 -O2/-Os CPU周期; 不构建 FPGA 位流。"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from ama.firmware import elf_to_rom, write_hex  # noqa: E402


def run(args, log):
    subprocess.run(list(map(str, args)), cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)


def main():
    out = ROOT / 'game/build/cpu-perf'
    out.mkdir(parents=True, exist_ok=True)
    tb = (ROOT / 'tests/cpu/cpu_tb.sv').read_text().replace('module cpu_tb;', 'module sd_perf_tb;')
    tb = tb.replace('cycles > 1000000', 'cycles > 30000000')
    tb = tb.replace(
        'end else if (da >= RAM_BASE',
        """end else if (da == 32'h20000000 && dwe) begin
                    $display("[frame] cycles=%0d", dw);
                    dpayload <= 0;
                end else if (da[31:28] == 3) begin
                    dpayload <= 0;
                end else if (da >= RAM_BASE""",
    )
    (out / 'sd_perf_tb.sv').write_text(tb)
    with (out / 'compile.log').open('w') as log:
        run(
            [
                'verilator',
                '--binary',
                '--timing',
                '-Wno-fatal',
                '--top-module',
                'sd_perf_tb',
                '-f',
                'rtl/cpu.f',
                out / 'sd_perf_tb.sv',
                '--Mdir',
                out / 'obj',
                '-o',
                'sim',
            ],
            log,
        )
    for opt in ('-O2', '-Os'):
        dest = out / opt[1:]
        dest.mkdir(exist_ok=True)
        elf = dest / 'app.elf'
        with (dest / 'compile.log').open('w') as log:
            run(
                [
                    'riscv64-elf-gcc',
                    '-march=rv32im_zicsr',
                    '-mabi=ilp32',
                    opt,
                    '-nostdlib',
                    '-ffreestanding',
                    '-fno-builtin',
                    '-msmall-data-limit=0',
                    '-mno-relax',
                    '-Wl,--nmagic',
                    '-Wl,--build-id=none',
                    '-Igame/core',
                    '-Igame/board',
                    '-Igame/build',
                    '-Ttests/cpu/link.ld',
                    'tests/cpu/start.S',
                    'game/tests/cpu_perf.c',
                    'game/core/touhou.c',
                    'game/core/fixed.c',
                    'game/core/hand.c',
                    'game/core/portrait.c',
                    'game/board/gfx_hw.c',
                    'game/board/mem.c',
                    '-lgcc',
                    '-o',
                    elf,
                ],
                log,
            )
        write_hex(elf_to_rom(elf), dest / 'rom.hex')
        ram = elf_to_rom(elf, base=0x10000000)
        write_hex(ram, dest / 'ram.hex')
        with (dest / 'run.log').open('w') as log:
            run([out / 'obj/sim', f'+rom={dest / "rom.hex"}', f'+ram={dest / "ram.hex"}'], log)
        cycles = list(map(int, re.findall(r'\[frame\] cycles=(\d+)', (dest / 'run.log').read_text())))
        assert len(cycles) == 8
        print(f'{opt}: mean={sum(cycles) // 8} max={max(cycles)} cycles/frame; {cycles}')


if __name__ == '__main__':
    main()
