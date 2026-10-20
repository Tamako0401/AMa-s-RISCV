"""本机配置 ama.local.toml: 工具命令、环境变量、默认板子。规则见 ama.local.toml.example。"""

import os
import tomllib

from .boards import ROOT

# ama 调用的外部程序; 键名就是程序名, 没配置就在 PATH 里找同名程序
TOOLS = [
    'riscv64-unknown-elf-gcc',
    'cc',
    'verilator',
    'vivado',
    'pds_shell',
    'ruff',
    'clang-tidy',
    'clang-format',
    'verible-verilog-lint',
    'verible-verilog-format',
]

LOCAL = ROOT / 'ama.local.toml'
CONFIG = tomllib.loads(LOCAL.read_text(encoding='utf8')) if LOCAL.exists() else {}
if unknown := CONFIG.keys() - {*TOOLS, 'env', 'board'}:
    raise SystemExit(
        f'ama.local.toml 里有不认识的项: {", ".join(sorted(unknown))} (可写: {", ".join(TOOLS)}, env, board)'
    )
os.environ.update(CONFIG.get('env', {}))


def tool(name):
    return CONFIG.get(name, [name])
