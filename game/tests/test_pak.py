#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""真实 mkfs.fat 镜像 + 同一份 C FAT/PAK 解析器。无需 root/mount/mtools。"""

import ctypes as C
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'game/tools'))
import pack  # noqa: E402

BLOCK = C.CFUNCTYPE(C.c_int, C.c_uint32, C.POINTER(C.c_uint8))


class Pak(C.Structure):
    _fields_ = [
        ('read', BLOCK),
        ('lba', C.c_uint32),
        ('size', C.c_uint32),
        ('count', C.c_uint32),
        ('cache_lba', C.c_uint32),
        ('block', C.c_uint8 * 512),
    ]


class Entry(C.Structure):
    _fields_ = [(name, C.c_uint32) for name in ('offset', 'length', 'loop_start', 'loop_end')]


def u16(b, off):
    return struct.unpack_from('<H', b, off)[0]


def u32(b, off):
    return struct.unpack_from('<I', b, off)[0]


def fat_image(path, payload):
    """让 mkfs.fat 建立真实 BPB/FAT, 仅测试夹具负责向空卷放文件。"""
    with path.open('wb') as f:
        f.truncate(64 * 1024 * 1024)
    subprocess.run(['mkfs.fat', '-F', '32', '-s', '1', str(path)], check=True, capture_output=True)
    image = bytearray(path.read_bytes())
    spc, reserved, fats, fs = image[13], u16(image, 14), image[16], u32(image, 36)
    data = reserved + fats * fs
    root = u32(image, 44)
    start = 10
    sectors = len(payload) // 512
    for fat in range(fats):
        off = (reserved + fat * fs) * 512
        for i in range(sectors):
            struct.pack_into('<I', image, off + (start + i) * 4, start + i + 1 if i + 1 < sectors else 0x0FFFFFFF)
    directory = (data + (root - 2) * spc) * 512
    struct.pack_into('<11sB14xHI', image, directory, b'AMA     PAK', 0x20, start, len(payload))
    # 低16位簇号在26, 高16位(20)仍为0。
    lba = data + (start - 2) * spc
    image[lba * 512 : lba * 512 + len(payload)] = payload
    path.write_bytes(image)
    return image, reserved, fs, data, directory, start


class PakTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='ama-pak-')
        cls.dir = Path(cls.tmp.name)
        pack.demo(cls.dir / 'assets')
        pack.pack(cls.dir / 'assets', cls.dir / 'AMA.PAK')
        cls.payload = (cls.dir / 'AMA.PAK').read_bytes()
        cls.fixture = fat_image(cls.dir / 'sd.img', cls.payload)
        lib = cls.dir / 'pak.so'
        subprocess.run(
            [
                'cc',
                '-std=c11',
                '-Wall',
                '-Wextra',
                '-Werror',
                '-shared',
                '-fPIC',
                str(ROOT / 'sw/components/sd/pak.c'),
                '-o',
                str(lib),
            ],
            check=True,
        )
        cls.lib = C.CDLL(str(lib))
        cls.lib.pak_mount.argtypes = [C.POINTER(Pak), BLOCK]
        cls.lib.pak_open.argtypes = [C.POINTER(Pak), BLOCK, C.c_uint32, C.c_uint32]
        cls.lib.pak_read.argtypes = [C.POINTER(Pak), C.c_uint32, C.c_void_p, C.c_uint32]
        cls.lib.pak_find.argtypes = [C.POINTER(Pak), C.c_uint32, C.c_uint32, C.POINTER(Entry)]

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def device(self, data, fail=None):
        @BLOCK
        def read(lba, dst):
            off = lba * 512
            if lba == fail or off + 512 > len(data):
                return 0
            C.memmove(dst, bytes(data[off : off + 512]), 512)
            return 1

        self.reader = read
        return read

    def mount(self, data, fail=None):
        self.p = Pak()
        return self.lib.pak_mount(C.byref(self.p), self.device(data, fail))

    def open(self, data):
        self.p = Pak()
        return self.lib.pak_open(C.byref(self.p), self.device(data), 0, len(data))

    def find(self, kind, id_=0):
        e = Entry()
        ok = self.lib.pak_find(C.byref(self.p), kind, id_, C.byref(e))
        return ok, e

    def test_sd_protocol_and_board_media(self):
        for name, sources, args in (
            ('sd_protocol', ['game/tests/sd_protocol.c', 'sw/components/sd/sd.c'], []),
            ('pcm_api', ['game/tests/pcm_api.c'], []),
            ('media', ['game/tests/media.c', 'sw/components/sd/pak.c'], [str(self.dir / 'AMA.PAK')]),
        ):
            executable = self.dir / name
            subprocess.run(
                [
                    'cc',
                    '-std=c11',
                    '-Wall',
                    '-Wextra',
                    '-Werror',
                    '-I' + str(ROOT / 'game/tests/fake'),
                    '-I' + str(ROOT / 'game/core'),
                    '-I' + str(ROOT / 'sw/drivers'),
                    '-I' + str(ROOT / 'sw/device'),
                    '-I' + str(ROOT / 'sw/components/sd'),
                    *[str(ROOT / src) for src in sources],
                    '-o',
                    str(executable),
                ],
                check=True,
            )
            subprocess.run([str(executable), *args], check=True)

    def test_real_fat32_and_all_bytes(self):
        self.assertEqual(self.mount(self.fixture[0]), 1)
        for kind in (1, 2):
            ok, e = self.find(kind)
            self.assertTrue(ok)
            result = (C.c_uint8 * e.length)()
            self.assertTrue(self.lib.pak_read(C.byref(self.p), e.offset, result, e.length))
            self.assertEqual(bytes(result), self.payload[e.offset : e.offset + e.length])
        self.assertEqual(self.find(1, 99)[0], 0)
        self.assertEqual(self.find(99)[0], 0)

    def test_file_backed_block_device(self):
        with (self.dir / 'sd.img').open('rb') as file:

            @BLOCK
            def read(lba, dst):
                file.seek(lba * 512)
                data = file.read(512)
                if len(data) != 512:
                    return 0
                C.memmove(dst, data, 512)
                return 1

            p = Pak()
            self.assertEqual(self.lib.pak_mount(C.byref(p), read), 1)
            data = (C.c_uint8 * len(self.payload))()
            self.assertEqual(self.lib.pak_read(C.byref(p), 0, data, len(data)), 1)
            self.assertEqual(bytes(data), self.payload)

    def test_mbr_partition(self):
        image = bytearray(2048 * 512) + self.fixture[0]
        struct.pack_into('<H', image, 510, 0xAA55)
        image[450] = 0x0C
        struct.pack_into('<II', image, 454, 2048, len(self.fixture[0]) // 512)
        self.assertEqual(self.mount(image), 1)
        self.assertEqual(self.p.lba, 2048 + self.fixture[3] + 8)

    def test_fragmented_rejected(self):
        image, reserved, _, _, _, start = self.fixture
        image = bytearray(image)
        struct.pack_into('<I', image, reserved * 512 + start * 4, start + 2)
        self.assertEqual(self.mount(image), 0)

    def test_root_chain(self):
        image, reserved, fs, data, directory, _ = self.fixture
        image = bytearray(image)
        image[(data + 1) * 512 : (data + 2) * 512] = image[directory : directory + 512]
        image[directory : directory + 512] = b'\xe5' * 512
        for f in range(2):
            struct.pack_into('<II', image, (reserved + f * fs) * 512 + 8, 3, 0x0FFFFFFF)
        self.assertEqual(self.mount(image), 1)
        # 自环必须有界返回。
        image[(data + 1) * 512 : (data + 2) * 512] = b'\xe5' * 512
        struct.pack_into('<I', image, reserved * 512 + 8, 2)
        self.assertEqual(self.mount(image), 0)

    def test_active_second_fat(self):
        image, reserved, fs, _, _, start = self.fixture
        image = bytearray(image)
        struct.pack_into('<H', image, 40, 0x81)
        struct.pack_into('<I', image, reserved * 512 + start * 4, 0)
        self.assertEqual(self.mount(image), 1)

    def test_missing_and_io_error(self):
        image = bytearray(self.fixture[0])
        image[self.fixture[4]] = 0
        self.assertEqual(self.mount(image), 0)
        self.assertEqual(self.mount(self.fixture[0], 0), 0)
        self.assertEqual(self.mount(self.fixture[0], self.fixture[1]), 0)

    def test_invalid_bpb(self):
        for off, fmt, value in (
            (11, 'H', 1024),
            (13, 'B', 3),
            (14, 'H', 0),
            (16, 'B', 0),
            (17, 'H', 512),
            (22, 'H', 10),
            (32, 'I', 1),
            (36, 'I', 0xFFFFFFFF),
            (42, 'H', 1),
            (44, 'I', 1),
            (510, 'H', 0),
        ):
            image = bytearray(self.fixture[0])
            struct.pack_into('<' + fmt, image, off, value)
            self.assertEqual(self.mount(image), 0, off)

    def test_pak_header_and_entry_bounds(self):
        for off, value in ((0, 0), (8, 2), (12, 65), (16, 512), (16, 0xFFFFFFFF)):
            data = bytearray(self.payload)
            struct.pack_into('<I', data, off, value)
            self.assertEqual(self.open(data), 0, off)
        for off, value in ((512 + 32, 0), (512 + 32, 1025), (512 + 36, 0xFFFFFFFF), (512 + 36, 10)):
            data = bytearray(self.payload)
            struct.pack_into('<I', data, off, value)
            self.assertEqual(self.open(data), 1)
            self.assertEqual(self.find(1)[0], 0)
        self.assertEqual(self.open(self.payload), 1)
        out = (C.c_uint8 * 4)()
        self.assertEqual(self.lib.pak_read(C.byref(self.p), 0xFFFFFFFF, out, 4), 0)
        self.assertEqual(self.lib.pak_read(C.byref(self.p), self.p.size - 1, out, 4), 0)

    def test_loop_bounds(self):
        for start, end, expected in ((0, 32000, 1), (4, 100, 1), (4, 0, 1), (1, 100, 0), (100, 4, 0), (0, 32004, 0)):
            data = bytearray(self.payload)
            struct.pack_into('<II', data, 512 + 64 + 40, start, end)
            self.assertEqual(self.open(data), 1)
            self.assertEqual(self.find(2)[0], expected)

    def test_portrait_reconstruct(self):
        self.assertEqual(self.open(self.payload), 1)
        _, e = self.find(1)
        import numpy as np
        from PIL import Image, ImageOps
        from refmodel import palettize
        import assets

        expected_pal, expected_idx = palettize(
            [
                assets.rgb565(
                    np.asarray(
                        ImageOps.contain(
                            Image.open(self.dir / 'assets/portraits/demo.png'), (64, 96), Image.Resampling.LANCZOS
                        )
                    )
                )
            ],
            128,
        )
        payload = self.payload[e.offset : e.offset + e.length]
        palette = np.frombuffer(payload[:256], dtype='<u2')
        tiles = np.frombuffer(payload[512:], dtype='u1')
        actual = np.vstack(
            (tiles[:4096].reshape(64, 64), np.hstack((tiles[4096:5120].reshape(32, 32), tiles[5120:].reshape(32, 32))))
        )
        # 与量化器的输出逐点一致, 无额外 SDL 调色。
        self.assertTrue(np.array_equal(actual, np.where(expected_idx[0] == 0, 0, expected_idx[0] + 127)))
        self.assertTrue(np.array_equal(palette, expected_pal[1:129]))


if __name__ == '__main__':
    unittest.main()
