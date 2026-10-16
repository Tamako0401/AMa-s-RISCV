"""把 ELF 做成 ROM 的 $readmemh 镜像 (sw/ 下的程序, 跑在 rtl/soc_top 上)。

用法: python3 scripts/elf2hex.py <程序.elf> <输出.hex> [--base 0x0] [--size 65536]

做的事:
  1. 读 ELF 的程序头 (program header)。每个 PT_LOAD 段写明了
     "文件里从哪开始、多少字节" 和 "要装到哪个物理地址 (p_paddr, 即 LMA)"。
  2. 物理地址落在 ROM 窗口 [base, base+size) 里的段, 按地址拷进一块 size 字节的镜像。
     sw/link.ld 里 .text 和 .data 的初值 (.data > RAM AT > ROM) 都在这里。
  3. 落在 ROM 之外的段 (例如 RAM 里的 .tohost) 不进镜像: RAM 上电不预装,
     .data 由 sw/startup.S 每次复位从 ROM 拷到 RAM。
  4. 没用到的地方填 0xa5 (不是合法指令, 跑飞了容易发现), 每行一个 32 位小端字。

输出就是 rom.v 的 ROM_INIT_FILE: 仿真时测试台用 +rom= 读入, 上板时 PDS 综合把它
作为片上存储 (DRM) 的初值写进位流。
"""
import argparse
import struct
from pathlib import Path

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


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('elf')
    parser.add_argument('hex')
    parser.add_argument('--base', type=lambda s: int(s, 0), default=0x0, help='ROM 起始地址')
    parser.add_argument('--size', type=lambda s: int(s, 0), default=65536, help='ROM 字节数')
    args = parser.parse_args()
    write_hex(elf_to_rom(args.elf, args.base, args.size), args.hex)


if __name__ == '__main__':
    main()
