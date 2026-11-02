#!/usr/bin/env python3
"""生成 MS7200 (板上 HDMI 接收芯片) 的 EDID, 打印成 C 数组, 贴进 sw/components/hdmi/ms7200.c。

用法: tools/edid.py
板子对电脑自称 "AMa FPGA", 首选 1280x720@60 (另外只声明 640x480@60):
电脑插上就自动出 720p, 显示设置里按名字认得出来, 不用手动改分辨率。
扩展块 (CEA-861) 只放必要的: 只收 RGB (不声明 YCbCr)、两个视频格式、HDMI 标识 (没有它电脑按 DVI 发)。
"""


def checksum(block):
    block.append((-sum(block)) & 0xFF)
    assert len(block) == 128 and sum(block) % 256 == 0
    return block


def descriptor(tag, text):
    """显示器名字 (0xFC) 等文字描述: 最多 13 字节, 换行结尾, 空格补齐"""
    raw = text.encode('ascii')[:13]
    raw = raw + b'\n' + b' ' * (12 - len(raw)) if len(raw) < 13 else raw
    return [0, 0, 0, tag, 0, *raw]


def base_block():
    b = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
    letters = [
        ord(c) - ord('A') + 1 for c in 'AMQ'
    ]  # 厂商代号: 3 个 5 位字母; AMA 已被别家注册 (hwdata pnp.ids), AMQ 没人用
    vendor = letters[0] << 10 | letters[1] << 5 | letters[2]
    b += [vendor >> 8, vendor & 0xFF, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]  # 产品号 1, 序列号 0 (不用)
    b += [44, 2026 - 1990]  # 生产周、年
    b += [1, 3]  # EDID 1.3
    b += [0x80, 0, 0, 0x78, 0x0E]  # 数字输入; 尺寸未知; gamma 2.2; RGB, sRGB, 首选时序在第一个描述符
    b += [0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54]  # 色度 (常见 sRGB 值)
    b += [0x20, 0x00, 0x00]  # 固定时序: 只有 640x480@60
    b += [0x01, 0x01] * 8  # 标准时序: 全空
    # 描述符 1: 1280x720@60 (CEA-861 VIC 4), 像素时钟 74.25 MHz
    b += [0x01, 0x1D, 0x00, 0x72, 0x51, 0xD0, 0x1E, 0x20, 0x6E, 0x28, 0x55, 0x00, 0, 0, 0, 0, 0, 0x1E]
    b += descriptor(0xFC, 'AMa FPGA')
    b += [
        0,
        0,
        0,
        0xFD,
        0,
        59,
        61,
        30,
        46,
        8,
        0,
        0x0A,
        0x20,
        0x20,
        0x20,
        0x20,
        0x20,
        0x20,
    ]  # 范围: 场 59~61 Hz, 行 30~46 kHz, 80 MHz
    b += [0, 0, 0, 0x10, 0] + [0] * 13  # 空描述符
    b += [1]  # 后面有 1 个扩展块
    return checksum(b)


def cea_block():
    video = [0x40 | 2, 4, 1]  # 视频数据块: 720p60, 640x480p60 (原生的是基本块的描述符 1)
    hdmi = [0x60 | 5, 0x03, 0x0C, 0x00, 0x10, 0x00]  # HDMI 厂商块: OUI 00-0C-03, 物理地址 1.0.0.0
    vcdb = [0xE0 | 2, 0x00, 0x4A]  # 视频能力块: RGB 量化范围可选 (免得电脑乱猜 16~235), 都不过扫描
    data = video + vcdb + hdmi
    b = [0x02, 0x03, 4 + len(data), 0x81] + data  # 默认不过扫描, 1 个原生时序; 只收 RGB, 不声明音频 (输入用不到)
    b += [0] * (127 - len(b))
    return checksum(b)


def main():
    edid = base_block() + cea_block()
    print(f'static const uint8_t edid[{len(edid)}] = {{')
    for i in range(0, len(edid), 16):
        print('    ' + ', '.join(f'0x{v:02X}' for v in edid[i : i + 16]) + ',')
    print('};')


if __name__ == '__main__':
    main()
