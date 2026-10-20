"""经串口 bootloader 把程序下载到板子上运行, 然后留在串口上显示程序输出 (Ctrl+] 退出)。

协议见 docs/bootloader.md。板子由串口芯片识别: FT2232 = EGO1, CP2102 = 盘古 MES50HP。

用法: python3 scripts/load.py <程序.elf> [串口] [--force]
    --force  板上位流的硬件版本号和本地源码对不上时也照样下载
以后并进 ama run。
"""

import struct
import sys
import time
import zlib
from pathlib import Path

import serial
from serial.tools import list_ports, miniterm

from .firmware import load_segments, hwid
from .boards import boards

APP_SIZE = 0xF800  # ROM 里 bootloader 之前的部分
USB = {tuple(data['usb']): name for name, data in boards().items()}


def app_image(elf):
    """ELF 里落在 app 区的段 -> 从 0 开始的镜像, 空隙填 0xa5 (同 elf2hex), 长度补到 4 的倍数"""
    segments = [(a, d) for a, d in load_segments(Path(elf).read_bytes()) if a < 0x10000000]
    end = max(a + len(d) for a, d in segments)
    if end > APP_SIZE:
        sys.exit(f'{elf}: 程序 {end} 字节, 超过 app 区 {APP_SIZE} 字节')
    image = bytearray(b'\xa5' * ((end + 3) & ~3))
    for addr, data in segments:
        image[addr : addr + len(data)] = data
    return bytes(image)


def find_board(port):
    """返回 (串口, 板名); port 为 None 时自动找"""
    for p in sorted(list_ports.comports(), key=lambda p: p.device, reverse=True):
        board = USB.get((p.vid, p.pid))
        # FT2232 有两个口, 串口是编号大的那个 (接口 0 是 JTAG), 所以倒序找第一个
        if board and (port is None or p.device == port):
            return p.device, board
    sys.exit(f'没找到板子的串口{f" {port}" if port else ""} (FT2232 = EGO1, CP2102 = 盘古)')


def enter_bootloader(ser):
    """break 让板子复位, 赶在 bootloader 的 200 ms 窗口里发 0x7F; 返回握手里的 HW_ID"""
    for _ in range(2):
        ser.break_condition = True
        time.sleep(0.02)
        ser.break_condition = False
        time.sleep(0.005)  # 等复位释放、bootloader 初始化好 UART
        ser.reset_input_buffer()
        ser.write(b'\x7f')
        reply = ser.read(12)
        if len(reply) == 12 and reply[:3] == b'AMB':
            version, hw, size = struct.unpack('<BII', reply[3:])
            if version != 1 or size != APP_SIZE:
                sys.exit(f'bootloader 协议版本 {version}、app 区 {size} 字节, 和本工具不配套')
            return hw
    sys.exit('板子没有回应 bootloader 握手: 位流里可能没有 bootloader (先重新构建、烧写位流), 或串口选错了')


def download(ser, image):
    crc = zlib.crc32(image)
    for _ in range(2):
        ser.write(b'W' + struct.pack('<II', len(image), crc) + image)
        ser.timeout = 2 + len(image) * 10 / ser.baudrate  # 传输时间 + 板子回读算 CRC
        reply = ser.read(1)
        if reply == b'K':
            return
        if reply == b'E':
            (board_crc,) = struct.unpack('<I', ser.read(4))
            print(f'校验失败: 电脑 0x{crc:08x}, 板子 0x{board_crc:08x}, 重试')
    sys.exit('下载失败')


def main(argv):
    force = '--force' in argv
    args = [a for a in argv if a != '--force']
    if not args:
        sys.exit(__doc__)
    image = app_image(args[0])
    port, board = find_board(args[1] if len(args) > 1 else None)
    ser = serial.Serial(port, 115200, timeout=0.3)
    hw = enter_bootloader(ser)
    local = hwid(board)
    if hw != local and not force:
        sys.exit(
            f'板上位流的硬件版本 0x{hw:08x} 和本地源码 0x{local:08x} 不一致: '
            f'先重新构建、烧写位流, 或者加 --force 照样下载'
        )
    start = time.monotonic()
    download(ser, image)
    ser.write(b'G')
    print(f'{board} {port}: 下载 {len(image)} 字节, {time.monotonic() - start:.1f} 秒. 以下是程序输出, Ctrl+] 退出')
    ser.timeout = None
    term = miniterm.Miniterm(ser, echo=False)
    term.set_rx_encoding('utf-8')
    term.set_tx_encoding('utf-8')
    term.start()
    term.join(True)
    term.close()


if __name__ == '__main__':
    main(sys.argv[1:])
