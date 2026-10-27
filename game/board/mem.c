/* -nostdlib 下没有 libc, 但 gcc 给大结构体清零 / 赋值时会调 memset、memcpy (*g = (touhou_t){0} 等) */
#include <stddef.h>
#include <stdint.h>

void *memset(void *dst, int c, size_t n)
{
    uint8_t *d = dst;
    if (!(((uintptr_t)d | n) & 3)) { /* 对齐时按字写: 清一局的游戏状态有 20 KB */
        uint32_t w = (uint8_t)c * 0x01010101u;
        for (uint32_t *p = dst; n; n -= 4)
            *p++ = w;
        return dst;
    }
    while (n--)
        *d++ = (uint8_t)c;
    return dst;
}

void *memcpy(void *dst, const void *src, size_t n)
{
    uint8_t *d = dst;
    const uint8_t *s = src;
    while (n--)
        *d++ = *s++;
    return dst;
}
