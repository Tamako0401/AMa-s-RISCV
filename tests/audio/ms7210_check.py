"""用主机模拟 I2C, 核对音频包和逐次故障后仍释放视频: python tests/audio/ms7210_check.py。"""

import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARNESS = r"""
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "ms7210.h"
static unsigned char regs[65536], packet[32];
static int call, fail_at, release_call, video_end, audio_start, packet_n;
void delay_ms(unsigned int ms) { (void)ms; }
int i2c_write_reg16(const i2c_pins_t *p, uint8_t dev, uint16_t reg, uint8_t v) {
    (void)p;
    assert(dev == 0xb2);
    ++call;
    if (reg == 0x000b && v == 0x11) release_call = call;
    if (reg == 0x0507 && v == 0) video_end = call;
    if (call == fail_at) return -1;
    regs[reg] = v;
    if (reg == 0x050a) packet_n = 0;
    if (reg == 0x050d && packet_n < 32) packet[packet_n++] = v;
    return 0;
}
int i2c_read_reg16(const i2c_pins_t *p, uint8_t dev, uint16_t reg, uint8_t *v) {
    (void)p;
    assert(dev == 0xb2);
    ++call;
    if (reg == 0x0503) audio_start = call;
    if (call == fail_at) return -1;
    *v = regs[reg];
    return 0;
}
static void reset(int fail) {
    memset(regs, 0xa5, sizeof regs);
    call = release_call = video_end = audio_start = packet_n = 0;
    fail_at = fail;
}
int main(void) {
    const i2c_pins_t pins = {0};
    reset(0);
    assert(ms7210_init(&pins) == 0);
    assert((regs[0x0531] & 0xff) == 0x84);
    assert((regs[0x0532] & 15) == 1);
    assert((regs[0x0535] & 0x30) == 0x10);
    assert((regs[0x0535] & ~0x30) == (0xa5 & ~0x30));
    assert(regs[0x050a] == 0x84 && regs[0x0509] == 1 && regs[0x050b] == 10);
    assert((regs[0x050e] & 0x60) == 0x60); /* AVI 和 audio 同时开 */
    assert(packet_n == 11 && packet[1] == 0x11 && packet[2] == 0x0d);
    unsigned sum = 0x84 + 1 + 10;
    for (int i = 0; i < packet_n; ++i) sum += packet[i];
    assert((sum & 255) == 0);
    int first = audio_start, release = release_call, end = video_end, last = call;
    /* 设置音频和写包期间每次 I2C 读/写分别失败一次。视频表本身不注错。 */
    int tested = 0;
    for (int i = first; i <= last; ++i) {
        if (i >= release && i <= end) continue;
        reset(i);
        assert(ms7210_init(&pins) == -1);
        assert(release_call != 0 && regs[0x000b] == 0x11 && regs[0x0507] == 0);
        ++tested;
    }
    printf("PASS MS7210: 48k/2ch/16bit InfoFrame, AVI preserved, %d I2C failures keep video\n", tested);
}
"""

with tempfile.TemporaryDirectory(prefix='ms7210-check-') as directory:
    out = Path(directory)
    (out / 'bsp.h').write_text('void delay_ms(unsigned int ms);\n')
    (out / 'check.c').write_text(HARNESS)
    executable = out / 'check'
    subprocess.run(
        [
            'cc',
            '-std=c11',
            '-Wall',
            '-Wextra',
            '-Werror',
            f'-I{out}',
            '-Isw/components/hdmi',
            '-Isw/drivers',
            'sw/components/hdmi/ms7210.c',
            str(out / 'check.c'),
            '-o',
            str(executable),
        ],
        cwd=ROOT,
        check=True,
    )
    subprocess.run([str(executable)], check=True)
