"""Run directed checks for known defects; FAIL is currently expected.

Requires clang, ld.lld, llvm-objcopy, iverilog and vvp. Generated artifacts live
in a temporary directory, leaving existing tests, RTL and build outputs alone.
"""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / 'tests/directed'


def run(*args, cwd=ROOT):
    result = subprocess.run([shutil.which(str(args[0])) or str(args[0]),
                             *map(str, args[1:])], cwd=cwd, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=60)
    if result.stdout:
        print(result.stdout, end='', flush=True)
    result.check_returncode()
    return result.stdout


def firmware(out, name, sources, linker):
    objects = []
    for n, source in enumerate(sources):
        obj = out / f'{name}-{n}.o'
        run('clang', '--target=riscv32-unknown-elf', '-march=rv32i_zicsr',
            '-mabi=ilp32', '-O2', '-ffreestanding', '-fno-builtin',
            '-fno-stack-protector', '-msmall-data-limit=0', '-mno-relax',
            '-c', source, '-o', obj)
        objects.append(obj)
    elf = out / f'{name}.elf'
    run('ld.lld', '-m', 'elf32lriscv', '--no-relax', '-T', linker,
        *objects, '-o', elf)
    binary = out / f'{name}.bin'
    sections = ['--only-section=.text'] if name == 'trap_stack' else []
    run('llvm-objcopy', '-O', 'binary', *sections, elf, binary)
    image = binary.read_bytes()
    if len(image) > 65536:
        raise ValueError(f'{name}: image exceeds 64 KiB')
    image += b'\xa5' * (65536 - len(image))
    path = out / f'{name}.hex'
    path.write_text(''.join(f'{int.from_bytes(image[n:n+4], "little"):08x}\n'
                            for n in range(0, len(image), 4)), encoding='ascii')
    return path


def board_sources(out):
    """Icarus 13 需要 spi_hit 先声明; 只在临时副本中移动原行。"""
    path = ROOT / 'rtl/soc/minimal_soc.v'
    source = path.read_text(encoding='utf8')
    declaration = '    wire spi_hit = da >= 32\'h40002000 && da <= 32\'h4000200f;\n'
    anchor = '    wire spi_ready;\n'
    source = source.replace(declaration, '').replace(anchor, declaration + anchor)
    path = out / 'minimal_soc-icarus.v'
    path.write_text(source, encoding='utf8')
    print('Icarus compatibility: move spi_hit net declaration earlier in temporary copy', flush=True)
    return ['-f', 'rtl/cpu.f', 'rtl/utils/vld_rdy.v', 'rtl/perips/gpio.v',
            'rtl/perips/uart.v', 'rtl/perips/spi.v', path,
            'boards/mes50hp/mes50hp_top.v']


def check(out, number, top):
    extra = []
    cwd = ROOT
    if number == 1:
        sources = ['-f', 'rtl/reusable.f']
    elif number == 2:
        image = firmware(out, 'trap_stack', [TESTS / 'trap_stack.S'],
                         ROOT / 'tests/cpu/link.ld')
        sources = ['-f', 'rtl/cpu.f']
        extra = [f'+rom={image.as_posix()}']
    else:
        firmware(out, 'board_reset', [ROOT / 'sw/board/start.S', TESTS / 'board_reset.c'],
                 ROOT / 'sw/board/link.ld')
        sources = board_sources(out)
        cwd = out  # minimal_soc 的 MEM_FILE 在此目录, 只在仿真启动时读取一次
    sim = out / f'{top}.vvp'
    run('iverilog', '-g2012', '-s', top, '-o', sim, *sources, TESTS / f'{top}.sv')
    output = run('vvp', sim, *extra, cwd=cwd)
    # $finish 返回 0, 因此必须解析 CHECK, 不把已知 RTL 失败反转为 PASS。
    checks = re.findall(r'^CHECK (\d+) (PASS|FAIL)(?:: (.*))?$', output, re.MULTILINE)
    if len(checks) != 1 or checks[0][0] != str(number):
        raise ValueError(f'expected exactly one CHECK {number} verdict')
    _, status, detail = checks[0]
    return status, detail or '符合检查规范'


def main():
    for tool in ['clang', 'ld.lld', 'llvm-objcopy', 'iverilog', 'vvp']:
        if not shutil.which(tool):
            raise SystemExit(f'Missing required tool: {tool}')
    cases = [(1, 'response_hold_tb', 'ROM、RAM/gen_ram 响应保持'),
             (2, 'trap_stack_tb', 'ECALL/MRET mstatus 栈'),
             (3, 'board_reset_tb', 'KEY1 后全局变量初值')]
    results = []
    print('已知缺陷预期 FAIL; 修复后应 PASS, 功能失败仍返回退出码 1。', flush=True)
    with tempfile.TemporaryDirectory(prefix='ama-directed-') as directory:
        out = Path(directory)
        for number, top, title in cases:
            print(f'\nRunning CHECK {number}: {title}', flush=True)
            try:
                status, detail = check(out, number, top)
            except (subprocess.SubprocessError, OSError, ValueError) as exc:
                status, detail = 'ERROR', str(exc).replace('\n', ' ')
            results.append((number, title, status, detail))
    print('\n| 编号 | 检查 | 结果 | 实际观察 |')
    print('| --- | --- | --- | --- |')
    for number, title, status, detail in results:
        print(f'| {number} | {title} | {status} | {detail.replace("|", "/")} |')
    passed = sum(status == 'PASS' for _, _, status, _ in results)
    failed = sum(status == 'FAIL' for _, _, status, _ in results)
    errors = sum(status == 'ERROR' for _, _, status, _ in results)
    print(f'\nTOTAL: {passed} PASS, {failed} FAIL, {errors} ERROR', flush=True)
    return 2 if errors else (1 if failed else 0)


if __name__ == '__main__':
    raise SystemExit(main())
