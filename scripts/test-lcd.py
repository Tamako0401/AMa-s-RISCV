"""编译并运行 LCD 点亮测试。

把 sw/ 下的真实 C 程序(默认 sw/app/lcd_demo)用 clang 编译、按 sw/link.ld 链接,
转成 ROM/RAM 两个 hex 镜像, 再跑在 rtl/soc_top 上; st7789_model 挂在真实 SPI
引脚上, 从引脚重建画面, 测试台核对关键像素。

依赖 Python 3、clang(--target=riscv32-unknown-elf)、ld.lld、llvm-objcopy、
iverilog、vvp。RISCV_CC 可指定其它 riscv32 编译器(如 riscv64-elf-gcc)。
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/lcd'

ROM_BYTES = 65536          # 与 rtl/soc_top/soc_top.v 的 u_rom 一致
RAM_BYTES = 65536          # 与 rtl/soc_top/soc_top.v 的 u_ram 一致

# sw/ 的分层源码, 与 justfile 的 sw_lib 保持一致
SW_SOURCES = [
    'sw/startup.S',
    'sw/drivers/spi.c',
    'sw/bsp/bsp.c',
    'sw/bsp/bsp_lcd.c',
    'sw/components/lcd/lcd.c',
    'sw/components/lcd/st7789.c',
    'sw/components/lcd/ili9341.c',
]
SW_INCLUDES = ['sw/device', 'sw/drivers', 'sw/bsp', 'sw/components/lcd']

# 屏幕初始化里的毫秒延时按真实计数要 2600 万拍, 纯仿真跑不动。
# bsp.c 的 SIM_CYCLE_DIV 把它缩到 2.6 万拍; 只影响仿真, 实机行为不变。
SIM_CYCLE_DIV = os.environ.get('SIM_CYCLE_DIV', '1000')


def run(*args):
    subprocess.run([shutil.which(str(args[0])) or str(args[0]),
                    *[str(a) for a in args[1:]]], cwd=ROOT, check=True)


def to_hex(image, path):
    path.write_text(''.join(f'{int.from_bytes(image[i:i+4], "little"):08x}\n'
                            for i in range(0, len(image), 4)), encoding='ascii')
    return path


def build_app(name):
    """C 程序 -> ELF -> ROM/RAM 两个 hex 镜像(按 sw/link.ld 的布局)。"""
    elf = BUILD / f'{name}.elf'
    cc = os.environ.get('RISCV_CC', 'clang')
    target = ['--target=riscv32-unknown-elf', '-fuse-ld=lld'] if 'clang' in cc else []
    run(cc, *target, '-march=rv32i_zicsr', '-mabi=ilp32', '-O2',
        '-nostdlib', '-ffreestanding', '-Wall', '-Wextra',
        '-msmall-data-limit=0', '-mno-relax',
        f'-DSIM_CYCLE_DIV={SIM_CYCLE_DIV}',
        *[f'-I{i}' for i in SW_INCLUDES],
        '-T', 'sw/link.ld', *SW_SOURCES, f'sw/app/{name}/main.c', '-o', elf)

    rom_bin = BUILD / f'{name}-rom.bin'
    ram_bin = BUILD / f'{name}-ram.bin'
    run('llvm-objcopy', '-O', 'binary', '--only-section=.text', elf, rom_bin)
    # sw/link.ld 把 .tohost 放在 RAM 窗口第 0 个字, 其后才是 .data,
    # 所以按 VMA 顺序导出这两个段就是 RAM 镜像的开头。
    run('llvm-objcopy', '-O', 'binary', '--only-section=.tohost',
        '--only-section=.data', elf, ram_bin)

    rom = rom_bin.read_bytes()
    if len(rom) > ROM_BYTES:
        raise ValueError(f'{name}: .text 超过 ROM ({len(rom)} > {ROM_BYTES})')
    rom += b'\xa5' * (ROM_BYTES - len(rom))     # 未初始化处填非法指令
    ram = ram_bin.read_bytes()
    if len(ram) > RAM_BYTES:
        raise ValueError(f'{name}: RAM 镜像超过容量 ({len(ram)} > {RAM_BYTES})')
    ram += b'\xa5' * (RAM_BYTES - len(ram))     # 便于发现"读到没写过的地方"
    return (to_hex(rom, BUILD / f'{name}.rom.hex'),
            to_hex(ram, BUILD / f'{name}.ram.hex'))


def main():
    app = sys.argv[1] if len(sys.argv) > 1 else 'lcd_demo'
    for tool in ['llvm-objcopy']:
        if not shutil.which(tool):
            raise SystemExit(f'Missing required tool: {tool}')
    BUILD.mkdir(parents=True, exist_ok=True)

    rom_hex, ram_hex = build_app(app)
    args = [f'+rom={rom_hex.as_posix()}', f'+ram={ram_hex.as_posix()}']

    # 一屏 240x320 要搬约 19 万字节, 即约 1200 万周期。iverilog 大约 2 万周期/秒,
    # 跑完要十几分钟; Verilator 快两个数量级, 所以优先用它, 没有才退回 iverilog。
    if shutil.which('verilator'):
        objdir = BUILD / 'obj'
        run('verilator', '--binary', '--timing', '-Wno-fatal',
            '--top-module', 'lcd_tb', '-f', 'rtl/soc.f',
            'tests/soc/st7789_model.sv', 'tests/soc/lcd_tb.sv',
            '--Mdir', objdir.as_posix(), '-o', 'lcd_tb_sim')
        run(str(objdir / 'lcd_tb_sim'), *args)
    else:
        print('警告: 没找到 verilator, 回退到 iverilog; 这一次大约要跑十几分钟。',
              file=sys.stderr, flush=True)
        for tool in ['iverilog', 'vvp']:
            if not shutil.which(tool):
                raise SystemExit(f'Missing required tool: {tool}')
        vvp = BUILD / 'lcd_tb.vvp'
        run('iverilog', '-g2012', '-s', 'lcd_tb', '-o', vvp,
            '-f', 'rtl/soc.f', 'tests/soc/st7789_model.sv', 'tests/soc/lcd_tb.sv')
        run('vvp', vvp, *args)


if __name__ == '__main__':
    main()
