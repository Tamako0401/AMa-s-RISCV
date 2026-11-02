#include "mix.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static int level, enabled, reads, fail;
static int8_t fifo[2048];
int mix_hw_space(void)
{
    return 2048 - level;
}
void mix_hw_enable(int on)
{
    enabled = on;
    if (!on)
        level = 0;
}
void mix_hw_write(const int8_t *data, int n)
{
    assert(enabled && !(n & 3) && n <= 2048 - level);
    memcpy(fifo + level, data, n);
    level += n;
}
static int music(uint32_t off, void *data, uint32_t n)
{
    (void)off;
    reads++;
    memset(data, fail ? 77 : 100, n); /* 故障可部分修改输出, 应丢弃该片段 */
    return !fail;
}
static void clip(const char *name, int value, unsigned n)
{
    int8_t *p = mix_reserve(n);
    assert(p);
    memset(p, value, n);
    assert(mix_commit(name, n));
}
static void check(int value)
{
    for (int i = 0; i < level; i++)
        assert(fifo[i] == value);
}
int main(void)
{
    mix_init();
    assert(!mix_play("missing", 1, 128));
    assert(!mix_reserve(0) && !mix_reserve(16004));
    clip("a", 100, 2000);
    clip("b", 100, 2000);
    clip("negative", -128, 2000);
    clip("c", 10, 2000);
    clip("d", 20, 2000);
    assert(!mix_reserve(4000));
    mix_play("a", 1, 128);
    mix_play("b", 1, 128);
    mix_frame();
    assert(level == MIX_TARGET);
    check(127);
    mix_frame();
    assert(level == MIX_TARGET); /* 达水位不再写 */
    level -= 267;
    memmove(fifo, fifo + 267, level);
    mix_frame();
    assert(level == 797);
    check(127); /* 整字向下补水 */
    mix_stop_sfx();
    level = 0;
    mix_play("negative", 1, 128);
    mix_play("a", 1, 128);
    mix_play("a", 1, 128); /* 重播仍只有一份 a */
    mix_frame();
    check(-28);
    mix_stop_sfx();
    level = 0;
    mix_play("a", 1, 128);
    mix_play("b", 2, 128);
    mix_play("c", 3, 128);
    mix_play("d", 4, 128);
    mix_play("negative", 1, 128); /* 同级满员丢弃 */
    mix_frame();
    check(127);
    level = 0;
    mix_play("negative", 5, 128); /* 抢掉 a: 100+10+20-128=2 */
    mix_frame();
    check(2);
    mix_stop_sfx();
    level = 0;
    mix_play("negative", 1, 128);
    mix_play("negative", 1, 128);
    mix_frame();
    check(-128);
    mix_stop_sfx();
    level = 0;
    mix_play("a", 1, 64);
    mix_frame();
    check(50);
    mix_stop_sfx();
    level = 0;
    mix_music(music, 0, 16000, 0, 0);
    mix_play("a", 1, 128);
    mix_frame();
    check(127);
    fail = 1;
    level = 0;
    mix_play("c", 3, 128);
    mix_frame();
    check(110);
    int before = reads;
    level = 0;
    mix_frame();
    assert(reads == before); /* 故障后音效不再读卡 */
    mix_stop_sfx();
    level = 0;
    mix_frame();
    assert(!enabled);
    mix_init();
    clip("neg1", -100, 1000);
    clip("neg2", -100, 1000);
    mix_play("neg1", 1, 128);
    mix_play("neg2", 1, 128);
    mix_frame();
    check(-128);
    mix_init();
    int8_t *p = mix_reserve(4);
    p[0] = 1;
    p[1] = 2;
    p[2] = 3;
    p[3] = 4;
    assert(mix_commit("short", 4));
    mix_play("short", 1, 128);
    mix_frame();
    assert(fifo[0] == 1 && fifo[3] == 4 && fifo[4] == 0);
    level = 0;
    mix_play("short", 1, 128);
    mix_frame();
    assert(fifo[0] == 1);
    puts("mix: saturation/watermark/restart/priority/volume/tail/read-failure/pool passed");
}
