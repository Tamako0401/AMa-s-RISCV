"""解释 tests.toml, 编译并运行仿真和电脑端测试。"""

import shlex
import subprocess
import time
import tomllib
from pathlib import Path

from .boards import ROOT
from .local import tool
from .firmware import SW_INC, build_firmware, CFLAGS, compiler, elf_to_rom, write_hex

OUT = ROOT / 'build/test'


def command(args, log):
    args = list(map(str, args))
    if args[0].endswith('.py'):  # Windows CreateProcess 不认 shebang, 经 uv 按内联依赖跑
        args = ['uv', 'run', '--script', *args]
    print('$ ' + shlex.join(args), file=log, flush=True)
    return subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT).returncode


def program(test, run, out, log):
    elf = out / 'program.elf'
    args = [
        *compiler(),
        *CFLAGS,
        '-march=rv32im_zicsr_zifencei',
        '-fno-stack-protector',
        *[f'-I{d}' for d in SW_INC],
        f'-DBOARD_{test.get("board", "mes50hp").upper()}',  # 测试程序也用 bsp.h 的 SYSCLK_HZ 定波特率
        *run.get('defines', []),
        '-T',
        run.get('link', 'tests/cpu/link.ld'),
        *run['program'],
        '-o',
        elf,
    ]
    if command(args, log):
        return False
    rom = elf_to_rom(elf)
    ram = bytearray(b'\xa5' * 65536)
    ram[:4] = bytes(4)
    # sw 的链接脚本把数据初值放在 ROM, 必须由真实 startup 拷贝。
    if run.get('ram_init', True):
        ram[:] = elf_to_rom(elf, base=0x10000000)
        ram[:4] = bytes(4)
    write_hex(rom, out / 'program-rom.hex')
    write_hex(ram, out / 'program-ram.hex')
    return True


def images(test, run, out, log):
    args = []
    if 'prepare' in run:  # 先跑命令生成测试数据 ({out} = 这次运行的输出目录)
        if command([a.replace('{out}', str(out)) for a in run['prepare']], log):
            return None
    if 'app' in run:
        # 编译失败算这个测试 FAIL, 编译日志在 log 里; 固件按测试项的板名编译 (默认 mes50hp)
        try:
            build_firmware(
                run['app'],
                test.get('board', 'mes50hp'),
                ['-DSIM_CYCLE_DIV=1000', *run.get('defines', [])],
                ['-DSIM_CYCLE_DIV=200'],
                out,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        except SystemExit:
            return None
        args.append(f'+rom={out / "rom.hex"}')
    if 'program' in run:
        if not program(test, run, out, log):
            return None
        prefix = 'program_' if 'app' in run else ''
        args += [f'+{prefix}rom={out / "program-rom.hex"}', f'+{prefix}ram={out / "program-ram.hex"}']
    return args + [a.replace('{out}', str(out)) for a in run.get('plusargs', [])]


def simulator(test, tb, params, out, log):
    rtl = test['rtl']
    sources = []
    for source in [rtl] if isinstance(rtl, str) else rtl:
        sources += ['-f', source] if source.endswith('.f') else [source]
    sources += test.get('extra', []) + [tb]
    args = [
        *tool('verilator'),
        '--binary',
        '--timing',
        '-Wno-fatal',
        '--top-module',
        tb.stem,
        *[f'-G{k}={v}' for k, v in params.items()],
        *test.get('vdefine', []),
        *sources,
        '--Mdir',
        out / 'obj',
        '-o',
        'sim',
    ]
    return None if command(args, log) else [out / 'obj/sim']


def report(name, ok, start, path):
    lines = path.read_text(errors='replace').splitlines()
    values = ' '.join(line.removeprefix('[result]').strip() for line in lines if line.startswith('[result]'))
    print(
        f'{"PASS" if ok else "FAIL"} {name} ({time.monotonic() - start:.2f}s)' + (f' {values}' if values else ''),
        flush=True,
    )
    if not ok:
        print(f'  日志: {path.relative_to(ROOT)}')
        print('\n'.join(lines[-30:]), flush=True)
    return ok


def bench(test, tb):
    results = []
    base = OUT / tb.relative_to(ROOT).with_suffix('')
    for index, params in enumerate(test.get('params', [{}])):
        out = base / str(index)
        out.mkdir(parents=True, exist_ok=True)
        start = time.monotonic()
        path = out / 'compile.log'
        with path.open('w') as log:
            executable = simulator(test, tb, params, out, log)
        if executable is None:
            results.append(report(f'{tb.relative_to(ROOT)} {params} compile', False, start, path))
            continue
        compile_time = time.monotonic() - start
        for number, run in enumerate(test.get('runs', [{}])):
            dest = out / str(number)
            dest.mkdir(parents=True, exist_ok=True)
            path = dest / 'test.log'
            start = time.monotonic() - compile_time
            with path.open('w') as log:
                plusargs = images(test, run, dest, log)
                ok = plusargs is not None
                if ok:
                    status = command([*executable, *plusargs], log)
                    ok = (status != 0) if test.get('expect') == 'fail' else (status == 0)
            label = run.get('app', ','.join(run.get('program', [])))
            detail = ' '.join(f'{k}={v}' for k, v in params.items())
            name = ' '.join(
                filter(
                    None,
                    [
                        str(tb.relative_to(ROOT)),
                        detail,
                        label,
                        '(预期失败)' if test.get('expect') == 'fail' else '',
                    ],
                )
            )
            results.append(report(name, ok, start, path))
    return results


def host(directory):
    app = directory.parent
    out = OUT / directory.relative_to(ROOT)
    out.mkdir(parents=True, exist_ok=True)
    path = out / 'test.log'
    start = time.monotonic()
    with path.open('w') as log:
        sources = sorted(directory.glob('*.c')) + sorted(p for p in app.glob('*.c') if p.name != 'main.c')
        ok = command([*tool('cc'), f'-I{app}', *sources, '-o', out / 'test'], log) == 0
        if ok:
            ok = command([out / 'test'], log) == 0
    return report(str(directory.relative_to(ROOT)), ok, start, path)


def test(paths):
    start = time.monotonic()
    selected = (
        [Path(p).resolve() for p in paths] if paths else [ROOT / 'tests', *sorted((ROOT / 'sw/app').glob('*/test'))]
    )
    configs, hosts = set(), set()
    for path in selected:
        if path.is_file():
            configs.add(path.parent / 'tests.toml')
        elif path.name == 'test' and path.parent.parent == ROOT / 'sw/app':
            hosts.add(path)
        else:
            configs.update(path.rglob('tests.toml'))
            hosts.update(p for p in path.rglob('test') if p.parent.parent == ROOT / 'sw/app')
    results = []
    for config in sorted(configs):
        for entry in tomllib.loads(config.read_text())['test']:
            tb = config.parent / entry['tb']
            if any(path == tb or path in tb.parents for path in selected):
                results += bench(entry, tb)
    results += [host(directory) for directory in sorted(hosts)]
    print(f'合计: {sum(results)} PASS, {len(results) - sum(results)} FAIL ({time.monotonic() - start:.2f}s)')
    return bool(results) and all(results)
