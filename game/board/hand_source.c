#include "hand_source.h"

handnet_t handnet;

__attribute__((weak)) void hand_source_init(pad_t *pad)
{
    (void)pad;
}

__attribute__((weak)) int hand_source(hand_raw_t *raw, uint32_t now_ms)
{
    (void)now_ms;
    return handnet_poll(&handnet, raw);
}
