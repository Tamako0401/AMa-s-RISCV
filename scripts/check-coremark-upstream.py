"""核对 CoreMark 原样文件, 哈希来自官方提交的原始文件。

来源: https://github.com/eembc/coremark/tree/1f483d5b8316753a742cbf5590caf5bd0a4e4777
UPSTREAM.md 是本仓库的来源说明, 不属于上游文件。
"""
import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHA256 = {
    'LICENSE.md': '9577b9c846f61fd69a0d8ac965998c6450c7d8969f71f0bb4a931b91aebad28a',
    'README.md': '5581fb67dc1609cbd1865f150dbcb1050d96c602987792456850eb96eb0dd08c',
    'core_list_join.c': 'ca00e4e010ece47d7f040cb92aa50a95345a00d3171b59d088f6b243be06ce7b',
    'core_main.c': '17884c93c5b94378eb0ff02b4df3725756cf2addb9b8cbcaa6200a4649ff5ca7',
    'core_matrix.c': 'ecdff717b5a5c4907d221a606760e25499899cbf617582c05d40db71c91351e4',
    'core_state.c': 'f4b84bb0a3452c45a4daa664ab502bfdccbd31cb57d93e9ac490c60937717a4e',
    'core_util.c': 'a3fbfcb9bb943b638624b8ece01c5836dd56a96d7bcde2697b248d077447327f',
    'coremark.h': '42642b9a06c7ed2b3bd9eda971b7c3868c4f5d27bf7ef6c4bba11291a0c2598a',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=ROOT / 'third_party/coremark',
                        help='待检查目录 (默认 third_party/coremark)')
    args = parser.parse_args()
    failures = []
    for name, expected in SHA256.items():
        path = args.directory / name
        if not path.is_file() or path.is_symlink():
            failures.append(f'{name}: 文件缺失或为符号链接')
        elif hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            failures.append(f'{name}: SHA-256 与官方提交不符')
    for path in args.directory.rglob('*'):
        if path.is_file() and path.relative_to(args.directory).as_posix() not in {*SHA256, 'UPSTREAM.md'}:
            failures.append(f'{path.relative_to(args.directory)}: 未列入上游清单')
    if failures:
        raise SystemExit('FAIL CoreMark 原样性检查:\n' + '\n'.join(failures))
    print(f'PASS CoreMark 原样性检查: {len(SHA256)} 个官方文件 SHA-256 一致')


if __name__ == '__main__':
    main()
