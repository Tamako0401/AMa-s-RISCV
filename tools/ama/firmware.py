"""固件编译、ROM 镜像和硬件版本号。"""

import json
import re
import shlex
import struct
import subprocess
import tomllib
import zlib
from pathlib import Path

from .boards import ROOT
from .local import tool

SW_LIB = [
    'sw/startup.S',
    'sw/drivers/spi.c',
    'sw/drivers/uart.c',
    'sw/bsp/bsp.c',
    'sw/components/key/key.c',
    'sw/components/lcd/lcd_io.c',
    'sw/components/lcd/lcd.c',
    'sw/components/lcd/st7789.c',
    'sw/components/lcd/st7735.c',
    'sw/components/lcd/ili9341.c',
]
SW_INC = ['sw/device', 'sw/drivers', 'sw/bsp', 'sw/components/key', 'sw/components/lcd']
CFLAGS = [
    '-march=rv32i_zicsr',
    '-mabi=ilp32',
    '-O2',
    '-nostdlib',
    '-ffreestanding',
    '-fno-builtin',
    '-Wall',
    '-Wextra',
    '-msmall-data-limit=0',
    '-mno-relax',
    # 不让 GNU ld 把 ELF 头放进加载段: 否则 bootloader 的段从 0xF000 开始, 拼 ROM 时会被丢掉
    '-Wl,--nmagic',
]

PT_LOAD = 1

ROM_SIZE, BOOT_SIZE = (
    int(re.search(rf'{name} = (0x[0-9a-f]+);', (ROOT / 'sw/memory.ld').read_text())[1], 16)
    for name in ['_rom_size', '_boot_size']
)
APP_SIZE = ROM_SIZE - BOOT_SIZE


def load_segments(elf):
    """返回 [(物理地址, 段内容)], 只取 PT_LOAD 段里文件中真实存在的字节。"""
    if elf[:4] != b'\x7fELF' or elf[4] != 1 or elf[5] != 1:
        raise SystemExit('只支持 32 位小端 ELF (rv32)')
    (phoff,) = struct.unpack_from('<I', elf, 0x1C)
    phentsize, phnum = struct.unpack_from('<HH', elf, 0x2A)
    segments = []
    for i in range(phnum):
        p_type, p_offset, _vaddr, p_paddr, p_filesz = struct.unpack_from('<5I', elf, phoff + i * phentsize)
        if p_type == PT_LOAD and p_filesz:
            segments.append((p_paddr, elf[p_offset : p_offset + p_filesz]))
    return segments


def elf_to_rom(elf_path, base=0x0, size=ROM_SIZE):
    """ELF -> size 字节的 ROM 镜像。超出 ROM 的段报错前先确认它确实不属于 ROM。"""
    image = bytearray(b'\xa5' * size)
    for addr, data in load_segments(Path(elf_path).read_bytes()):
        if addr + len(data) <= base or addr >= base + size:
            continue  # RAM 等其它窗口的段, 不进 ROM 镜像
        if addr < base:
            raise SystemExit(f'{elf_path}: 0x{addr:08x} 起的段跨进了 0x{base:08x} 起的 ROM 区')
        offset = addr - base
        if offset + len(data) > size:
            raise SystemExit(f'{elf_path}: 0x{addr:08x} 起 {len(data)} 字节超出 ROM ({size} 字节)')
        image[offset : offset + len(data)] = data
    return bytes(image)


def write_hex(image, hex_path):
    Path(hex_path).write_text(
        ''.join(f'{int.from_bytes(image[i : i + 4], "little"):08x}\n' for i in range(0, len(image), 4)),
        encoding='ascii',
    )


SUFFIXES = {'.v', '.vh', '.sv', '.xdc', '.fdc', '.csv', '.c', '.h', '.S', '.ld', '.f', '.toml'}


def hwid(board):
    crc = 0
    for top in [
        'rtl',
        f'boards/{board}',
        'sw/boot',
        'sw/device',
        'sw/bsp/bsp.h',
        f'sw/bsp/{board}_pins.h',
        'sw/memory.ld',
    ]:
        for path in sorted((ROOT / top).rglob('*')) if (ROOT / top).is_dir() else [ROOT / top]:
            if path.suffix in SUFFIXES and path.is_file():
                crc = zlib.crc32(path.relative_to(ROOT).as_posix().encode(), crc)
                crc = zlib.crc32(path.read_bytes().replace(b'\r\n', b'\n'), crc)
    return crc


def compiler():
    return tool('riscv64-unknown-elf-gcc')


def run(*cmd, check=True, **kw):
    cmd = [str(c) for c in cmd]
    if not kw.get('capture_output'):
        print('  $ ' + shlex.join(cmd), file=kw.get('stdout'), flush=True)
    try:
        result = subprocess.run(cmd, **kw)
    except FileNotFoundError:
        raise SystemExit(f'找不到 {cmd[0]}: 装上它, 或在 ama.local.toml 里写它的命令')
    if check and result.returncode:
        raise SystemExit('上面的命令失败了')
    return result


def check_app(app):
    if not (ROOT / 'sw/app' / app).is_dir():
        apps = sorted(p.name for p in (ROOT / 'sw/app').iterdir() if p.is_dir())
        raise SystemExit(f'没有这个程序: sw/app/{app}\n  现有: {" ".join(apps)}')


def firmware_dir(app, board):
    return ROOT / 'build/fw' / board / app


def compile_app(app, board, defines, out, **kw):
    check_app(app)
    out.mkdir(parents=True, exist_ok=True)
    app_dir = ROOT / 'sw/app' / app
    board_dir = app_dir / 'boards' / board
    config_path = app_dir / 'app.toml'
    config = tomllib.loads(config_path.read_text()) if config_path.exists() else {}
    sources = SW_LIB + sorted(str(p.relative_to(ROOT)) for d in [app_dir, board_dir] for p in d.glob('*.c'))
    sources += config.get('sources', [])
    include = SW_INC + [str(app_dir.relative_to(ROOT))] + config.get('include', [])
    if board_dir.is_dir():
        include.append(str(board_dir.relative_to(ROOT)))
    options = [
        *CFLAGS,
        *config.get('cflags', []),
        *[f'-I{d}' for d in include],
        f'-DBOARD_{board.upper()}',
        *defines,
    ]
    cmd = compiler()
    elf = out / 'app.elf'
    run(*cmd, *options, '-T', 'sw/link.ld', *sources, '-lgcc', '-o', elf, cwd=ROOT, **kw)
    # clangd 需要与实际编译一致的宏和头文件路径; 合并而不是覆盖, 别的程序的文件也能跳转
    database = ROOT / 'build/compile_commands.json'
    entries = {e['file']: e for e in json.loads(database.read_text())} if database.exists() else {}
    for src in sources:
        entries[src] = {'directory': str(ROOT), 'file': src, 'arguments': [*cmd, *options, '-c', src]}
    database.write_text(json.dumps(list(entries.values()), ensure_ascii=False, indent=1))
    return elf


def build_firmware(app, board, defines, boot_defines, out, **kw):
    """app + bootloader -> out/rom.hex, 分区见 sw/memory.ld。"""
    elf = compile_app(app, board, defines, out, **kw)
    boot = out / 'boot.elf'
    options = [f for f in CFLAGS if f != '-O2']
    run(
        *compiler(),
        *options,
        '-Os',
        '-fno-delete-null-pointer-checks',
        *boot_defines,
        *[f'-I{d}' for d in SW_INC],
        '-T',
        'sw/boot/link.ld',
        'sw/boot/startup.S',
        'sw/boot/main.c',
        '-lgcc',
        '-o',
        boot,
        cwd=ROOT,
        **kw,
    )
    size = max(addr + len(data) - APP_SIZE for addr, data in load_segments(boot.read_bytes()) if addr < ROM_SIZE)
    if size > BOOT_SIZE:
        raise SystemExit(f'bootloader too large: {size} bytes')
    write_hex(elf_to_rom(elf, size=APP_SIZE) + elf_to_rom(boot, base=APP_SIZE, size=BOOT_SIZE), out / 'rom.hex')
    return elf
