"""本机配置 ama.local.toml: 工具命令、环境变量、默认板子、程序的本机附加编译项。规则见 ama.local.toml.example。"""

import os
import tomllib

from .boards import ROOT

# ama 调用的外部程序; 键名就是程序名, 没配置就在 PATH 里找同名程序
TOOLS = [
    'riscv32-unknown-elf-gcc',
    'cc',
    'verilator',
    'vivado',
    'pds_shell',
    'cdt_cfg_shell',
    'ruff',
    'clang-tidy',
    'clang-format',
    'verible-verilog-lint',
    'verible-verilog-format',
]

LOCAL = ROOT / 'ama.local.toml'
CONFIG = tomllib.loads(LOCAL.read_text(encoding='utf8')) if LOCAL.exists() else {}
if unknown := CONFIG.keys() - {*TOOLS, 'env', 'board', 'app'}:
    raise SystemExit(
        f'ama.local.toml 里有不认识的项: {", ".join(sorted(unknown))} (可写: {", ".join(TOOLS)}, env, board, app)'
    )
os.environ.update(CONFIG.get('env', {}))


def tool(name):
    return CONFIG.get(name, [name])


def app_local(app):
    """[app.<程序>]: 本机给这个程序附加的 sources、include、cflags (调试、实验用, 不进仓库)"""
    extra = CONFIG.get('app', {}).get(app, {})
    if unknown := extra.keys() - {'sources', 'include', 'cflags'}:
        raise SystemExit(f'ama.local.toml 的 [app.{app}] 里有不认识的项: {", ".join(sorted(unknown))}')
    return extra
