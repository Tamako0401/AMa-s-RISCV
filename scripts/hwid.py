"""硬件版本号: 板子上的位流是不是用当前源码构建的。

构建位流时把它算出来, 作为 soc_top 的 HW_ID 参数固化进去 (bootloader 握手时报出来);
下载程序时电脑用同样的方法从本地源码再算一遍, 对不上就说明板上的位流旧了, 要先重新构建。

参与计算的是会进位流的所有源码: rtl/、boards/<板>/、sw/boot/ (bootloader 跟位流一起固化),
以及 bootloader 引用的 sw/device/、sw/bsp/bsp.h。
换行统一成 \\n, 这样 Windows 上 git 检出成 CRLF 也算出同一个值。

用法: python3 scripts/hwid.py <板>    打印 0x 开头的 8 位十六进制
"""
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUFFIXES = {'.v', '.vh', '.sv', '.xdc', '.fdc', '.csv', '.c', '.h', '.S', '.ld'}


def hwid(board):
    crc = 0
    for top in ['rtl', f'boards/{board}', 'sw/boot', 'sw/device', 'sw/bsp/bsp.h']:
        for path in sorted((ROOT / top).rglob('*')) if (ROOT / top).is_dir() else [ROOT / top]:
            if path.suffix in SUFFIXES and path.is_file():
                crc = zlib.crc32(path.relative_to(ROOT).as_posix().encode(), crc)
                crc = zlib.crc32(path.read_bytes().replace(b'\r\n', b'\n'), crc)
    return crc


if __name__ == '__main__':
    print(f'0x{hwid(sys.argv[1]):08x}')
