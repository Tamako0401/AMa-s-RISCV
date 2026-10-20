"""源码规范检查和格式化。"""
from .boards import ROOT
from .firmware import run
from .local import tool


def sources():
    groups = [
        [ROOT / 'ama', *(ROOT / 'tools/ama').rglob('*.py'), *(ROOT / 'sim').glob('*.py')],
        [p for p in (ROOT / 'sw').rglob('*') if p.suffix in {'.c', '.h'}],
        [p for top in ['rtl', 'boards', 'tests', 'sim']
         for p in (ROOT / top).rglob('*') if p.suffix in {'.v', '.sv'}],
    ]
    return [[str(p.relative_to(ROOT)) for p in sorted(paths)
             if not {'third_party', 'legacy', 'build'} & set(p.relative_to(ROOT).parts)
             and not p.match('boards/*/pins*')
             and not (p.parent == ROOT / 'sw/bsp' and (p.name.startswith('pins') or p.stem.endswith('_pins')))]
            for paths in groups]


def lint(fix):
    python, c, verilog = sources()
    commands = [
        ('ruff', ['check', *(['--fix'] if fix else []), *python]),
        *[('clang-tidy', ['-p', 'build', '--warnings-as-errors=*', *(['--fix'] if fix else []), path]) for path in c],
        *[('verible-verilog-lint', [*(['--autofix=inplace'] if fix else []), path]) for path in verilog],
        ('verilator', ['--lint-only', '-Wall', '-f', 'rtl/soc.f', '--top-module', 'soc_top']),
    ]
    passed = True
    for name, args in commands:
        result = run(*tool(name), *args, cwd=ROOT, check=False)
        passed = passed and result.returncode == 0
    return passed


def fmt(fix):
    commands = [
        ('ruff', ['format', *([] if fix else ['--check'])]),
        ('clang-format', ['-i'] if fix else ['--dry-run', '--Werror']),
        ('verible-verilog-format', ['--flagfile=.verible-format', '--inplace' if fix else '--verify']),
    ]
    passed = True
    for (name, args), paths in zip(commands, sources()):
        for path in paths:
            result = run(*tool(name), *args, path, cwd=ROOT, check=False, capture_output=True, text=True)
            if result.returncode:
                print(path)
                if fix:
                    print(result.stdout + result.stderr, end='')
                passed = False
    return passed
