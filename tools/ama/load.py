"""经串口 bootloader 把程序下载到板子 (协议见 docs/bootloader.md)。"""

import struct
import sys
import time
import zlib
from pathlib import Path


from .firmware import load_segments

APP_SIZE = 0xF800  # ROM 里 bootloader 之前的部分


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

