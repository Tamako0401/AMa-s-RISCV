"""编译并运行 LCD 点亮测试。

把 sw/ 下的真实 C 程序(默认 sw/app/lcd_demo)用 clang 编译、按 sw/link.ld 链接,
用 scripts/elf2hex.py 转成 ROM 的 hex 镜像, 再跑在 rtl/soc_top 上; st7789_model 挂在真实 SPI
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

# sw/ 的分层源码, 与 justfile 的 sw_lib 保持一致
SW_SOURCES = [
    'sw/startup.S',
    'sw/drivers/spi.c',
    'sw/drivers/uart.c',
    'sw/bsp/bsp.c',
    'sw/components/lcd/lcd_io.c',
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


def build_app(name):
    """C 程序 -> ELF -> ROM 的 hex 镜像(按 sw/link.ld 的布局)。"""
    elf = BUILD / f'{name}.elf'
    cc = os.environ.get('RISCV_CC', 'clang')
    target = ['--target=riscv32-unknown-elf', '-fuse-ld=lld'] if 'clang' in cc else []
    run(cc, *target, '-march=rv32i_zicsr', '-mabi=ilp32', '-O2',
        '-nostdlib', '-ffreestanding', '-Wall', '-Wextra',
        '-msmall-data-limit=0', '-mno-relax',
        f'-DSIM_CYCLE_DIV={SIM_CYCLE_DIV}',
        *[f'-I{i}' for i in SW_INCLUDES],
        '-T', 'sw/link.ld', *SW_SOURCES, f'sw/app/{name}/main.c', '-o', elf)

    # ELF -> ROM 镜像由 scripts/elf2hex.py 单独负责; RAM 不预装 (.data 由 startup.S 从 ROM 拷)
    rom_hex = BUILD / f'{name}.rom.hex'
    run(sys.executable, 'scripts/elf2hex.py', elf, rom_hex, '--size', ROM_BYTES)
    return rom_hex


def main():
    # 用法: test-lcd.py [程序名] [--tb 测试台]; 默认 lcd_demo 跑在 lcd_tb 上
    argv = sys.argv[1:]
    tb = 'lcd_tb'
    if '--tb' in argv:
        i = argv.index('--tb')
        tb = argv[i + 1]
        del argv[i:i + 2]
    app = argv[0] if argv else 'lcd_demo'
    BUILD.mkdir(parents=True, exist_ok=True)

    rom_hex = build_app(app)
    args = [f'+rom={rom_hex.as_posix()}']

    # 一屏 240x320 要搬约 19 万字节, 即约 1200 万周期。iverilog 大约 2 万周期/秒,
    # 跑完要十几分钟; Verilator 快两个数量级, 所以优先用它, 没有才退回 iverilog。
    if shutil.which('verilator'):
        objdir = BUILD / f'obj-{tb}'
        run('verilator', '--binary', '--timing', '-Wno-fatal',
            '--top-module', tb, '-f', 'rtl/soc.f',
            'tests/soc/st7789_model.sv', f'tests/soc/{tb}.sv',
            '--Mdir', objdir.as_posix(), '-o', f'{tb}_sim')
        run(str(objdir / f'{tb}_sim'), *args)
    else:
        print('警告: 没找到 verilator, 回退到 iverilog; 这一次大约要跑十几分钟。',
              file=sys.stderr, flush=True)
        for tool in ['iverilog', 'vvp']:
            if not shutil.which(tool):
                raise SystemExit(f'Missing required tool: {tool}')
        vvp = BUILD / f'{tb}.vvp'
        run('iverilog', '-g2012', '-s', tb, '-o', vvp,
            '-f', 'rtl/soc.f', 'tests/soc/st7789_model.sv', f'tests/soc/{tb}.sv')
        run('vvp', vvp, *args)


if __name__ == '__main__':
    main()
