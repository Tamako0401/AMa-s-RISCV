#include "gfx.h"
/* 固定三块: 64x64、32x32、32x32, 半分辨率存储, 放大两倍拼成128x192。 */
void gfx_portrait(int32_t x, int32_t y, uint32_t alpha)
{
    if (!gfx_portrait_ready())
        return;
    for (int i = 0; i < 3; i++) {
        gfx_sprite_t *s = gfx_sprite(x + (i == 0 ? 64 : i == 1 ? 32 : 96), y + (i ? 160 : 64), 1000 + i);
        s->flags = GFX_AFFINE | GFX_ALPHA;
        s->scale = 32;
        s->alpha = (uint8_t)(alpha < 16 ? alpha : 16);
    }
}
