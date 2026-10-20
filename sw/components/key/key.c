#include "key.h"
#include "bsp.h"
#include "io.h"

void key_ticks(key_t *keys, int key_num)
{
    static uint32_t last_sample;

    /* 先清掉上一轮的边沿: 两次采样之间主循环会跑很多轮, 边沿只该在一轮里出现 */
    for (key_t *kp = keys; kp < keys + key_num; kp++)
        kp->last = kp->now;

    if (bsp_cycles() - last_sample < bsp_ms_to_cycles(KEY_SAMPLE_MS))
        return;
    last_sample = bsp_cycles();

    for (key_t *kp = keys; kp < keys + key_num; kp++) {
        int read = io_read(kp->pin);
        if (read == kp->now)
            kp->debounce_cnt = 0;
        else if (++kp->debounce_cnt >= DEBOUNCE_TICKS) {
            kp->now = read;
            kp->debounce_cnt = 0;
        }
    }
}
