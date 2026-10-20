"""固件编译、ROM 镜像和硬件版本号。"""
import json
import shlex
import shutil
import struct
import subprocess
import tomllib
import zlib
from pathlib import Path

from .boards import ROOT

SW_LIB = ['sw/startup.S', 'sw/drivers/spi.c', 'sw/drivers/uart.c', 'sw/bsp/bsp.c',
          'sw/components/key/key.c', 'sw/components/lcd/lcd_io.c', 'sw/components/lcd/lcd.c', 'sw/components/lcd/st7789.c',
          'sw/components/lcd/st7735.c', 'sw/components/lcd/ili9341.c']
SW_INC = ['sw/device', 'sw/drivers', 'sw/bsp', 'sw/components/key', 'sw/components/lcd']
CFLAGS = ['--target=riscv32-unknown-elf', '-march=rv32i_zicsr', '-mabi=ilp32', '-O2',
          '-nostdlib', '-ffreestanding', '-fno-builtin', '-Wall', '-Wextra',
          '-msmall-data-limit=0', '-mno-relax', '-fuse-ld=lld']

PT_LOAD = 1


def load_segments(elf):
    """返回 [(物理地址, 段内容)], 只取 PT_LOAD 段里文件中真实存在的字节。"""
    if elf[:4] != b'\x7fELF' or elf[4] != 1 or elf[5] != 1:
        raise SystemExit('只支持 32 位小端 ELF (rv32)')
    phoff, = struct.unpack_from('<I', elf, 0x1c)
    phentsize, phnum = struct.unpack_from('<HH', elf, 0x2a)
    segments = []
    for i in range(phnum):
        p_type, p_offset, _vaddr, p_paddr, p_filesz = struct.unpack_from(
            '<5I', elf, phoff + i * phentsize)
        if p_type == PT_LOAD and p_filesz:
            segments.append((p_paddr, elf[p_offset:p_offset + p_filesz]))
    return segments


def elf_to_rom(elf_path, base=0x0, size=65536):
    """ELF -> size 字节的 ROM 镜像。超出 ROM 的段报错前先确认它确实不属于 ROM。"""
    image = bytearray(b'\xa5' * size)
    for addr, data in load_segments(Path(elf_path).read_bytes()):
        if not base <= addr < base + size:
            continue                      # RAM 等其它窗口的段, 不进 ROM 镜像
        offset = addr - base
        if offset + len(data) > size:
            raise SystemExit(f'{elf_path}: 0x{addr:08x} 起 {len(data)} 字节超出 ROM ({size} 字节)')
        image[offset:offset + len(data)] = data
    return bytes(image)


def write_hex(image, hex_path):
    Path(hex_path).write_text(''.join(f'{int.from_bytes(image[i:i+4], "little"):08x}\n'
                                      for i in range(0, len(image), 4)), encoding='ascii')


SUFFIXES = {'.v', '.vh', '.sv', '.xdc', '.fdc', '.csv', '.c', '.h', '.S', '.ld'}


def hwid(board):
    crc = 0
    for top in ['rtl', f'boards/{board}', 'sw/boot', 'sw/device', 'sw/bsp/bsp.h']:
        for path in sorted((ROOT / top).rglob('*')) if (ROOT / top).is_dir() else [ROOT / top]:
            if path.suffix in SUFFIXES and path.is_file():
                crc = zlib.crc32(path.relative_to(ROOT).as_posix().encode(), crc)
                crc = zlib.crc32(path.read_bytes().replace(b'\r\n', b'\n'), crc)
    return crc


def compiler(cc):
    candidates = ['clang'] if cc == 'clang' else [
        'riscv32-unknown-elf-gcc', 'riscv64-unknown-elf-gcc', 'riscv64-elf-gcc']
    for candidate in candidates:
        if path := shutil.which(candidate):
            return path
    raise SystemExit(f'找不到编译器: {", ".join(candidates)}')


def run(*cmd, **kw):
    cmd = [str(c) for c in cmd]
    print('  $ ' + shlex.join(cmd), flush=True)
    if subprocess.run(cmd, **kw).returncode:
        raise SystemExit('上面的命令失败了')


def check_app(app):
    if not (ROOT / 'sw/app' / app).is_dir():
        apps = sorted(p.name for p in (ROOT / 'sw/app').iterdir() if p.is_dir())
        raise SystemExit(f'没有这个程序: sw/app/{app}\n  现有: {" ".join(apps)}')


def flags(cc):
    return [f for f in CFLAGS if cc == 'clang' or not f.startswith(('--target=', '-fuse-ld='))]


def variant(app, cc):
    return app + ('-gcc' if cc == 'gcc' else '')


def firmware_dir(app, board, cc):
    return ROOT / 'build/fw' / board / variant(app, cc)


def compile_app(app, board, cc, defines, out):
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
    options = [*flags(cc), *config.get('cflags', []), *[f'-I{d}' for d in include],
               f'-DBOARD_{board.upper()}', *defines]
    cmd = compiler(cc)
    elf = out / 'app.elf'
    run(cmd, *options, '-T', 'sw/link.ld', *sources, *(['-lgcc'] if cc == 'gcc' else []), '-o', elf, cwd=ROOT)
    # clangd 需要与实际编译一致的宏和头文件路径。
    (ROOT / 'build/compile_commands.json').write_text(json.dumps([
        {'directory': str(ROOT), 'file': src, 'arguments': [cmd, *[f for f in options if not f.startswith('-fuse-ld')], '-c', src]}
        for src in sources], ensure_ascii=False, indent=1))
    return elf


def build_firmware(app, board, cc):
    out = firmware_dir(app, board, cc)
    elf = compile_app(app, board, cc, [], out)
    boot = out / 'boot.elf'
    options = [f for f in flags(cc) if f != '-O2']
    run(compiler(cc), *options, '-Os', '-fno-delete-null-pointer-checks',
        *[f'-I{d}' for d in SW_INC], '-T', 'sw/boot/link.ld',
        'sw/boot/startup.S', 'sw/boot/main.c', *(['-lgcc'] if cc == 'gcc' else []), '-o', boot, cwd=ROOT)
    size = max(addr + len(data) - 0xf800 for addr, data in load_segments(boot.read_bytes()) if addr < 0x10000)
    if size > 2048:
        raise SystemExit(f'bootloader too large: {size} bytes')
    print(f'Bootloader: {size} bytes', flush=True)
    write_hex(elf_to_rom(elf, size=0xf800) + elf_to_rom(boot, base=0xf800, size=2048), out / 'rom.hex')
    return elf
