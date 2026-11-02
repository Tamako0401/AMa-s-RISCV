#include "handnet.h"
#include "nn_post.h"

int handnet_poll(handnet_t *n, hand_raw_t *raw)
{
    if (!n->started) {
        n->started = 1;
        nn_capture();
        return 0;
    }
    uint32_t status = NN->STATUS;
    if (status & NN_STATUS_CAPTURE_ERROR) { /* 坏帧: 没推理, 再抓 */
        n->errors++;
        nn_capture();
        return 0;
    }
    if (status & NN_STATUS_BUSY) /* 在等帧、抓帧或推理 */
        return 0;
    if (!(status & NN_STATUS_DONE)) { /* 闲着又没结果 (不该有): 重新抓 */
        nn_capture();
        return 0;
    }
    nn_hand_t h;
    nn_decode(&h);
    nn_capture(); /* 抓帧请求同时清掉 DONE */
    n->results++;
    raw->seq = n->results;
    n->heat = (uint8_t)h.heat;
    raw->found = (int8_t)h.found;
    raw->fist = (int8_t)h.fist;
    raw->x = (int16_t)(h.x * 4);
    raw->y = (int16_t)(h.y * 4);
    return 1;
}
