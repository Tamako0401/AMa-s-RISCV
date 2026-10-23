/* 从本机 UDP 收手的识别结果 (model/hand_send.py 发), 代替板上的视觉寄存器。
 * 两种包, 全部小端:
 *   "HAND", seq (u32), found (i8), fist (i8), x, y (i16, 640x480 摄像头坐标)
 *   "HIMG", 起始行 (u8), 行数 (u8), 这些行的 160x120 BGR 小图 (摄像头小窗); macOS 一个 UDP 包最多约 9 KB, 所以分几包发 */
#include <arpa/inet.h>
#include <fcntl.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include "gfx.h"
#include "hand_udp.h"

#define HEADER 14
#define ROW (GFX_WINDOW_W * 3)

static int sock = -1;
static uint8_t packet[9216];
static uint8_t image_buf[GFX_WINDOW_H * ROW];

int hand_udp_open(int port)
{
    sock = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons((uint16_t)port)};
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (sock < 0 || bind(sock, (struct sockaddr *)&addr, sizeof addr) < 0)
        return -1;
    fcntl(sock, F_SETFL, O_NONBLOCK);
    return 0;
}

int hand_udp_poll(hand_raw_t *raw, const uint8_t **image)
{
    int got = 0;
    ssize_t n;
    while (sock >= 0 && (n = recv(sock, packet, sizeof packet, 0)) > 0) { /* 积压的包只要最新的 */
        if (n >= 6 && memcmp(packet, "HIMG", 4) == 0) {
            int row0 = packet[4], rows = packet[5];
            if (row0 + rows <= GFX_WINDOW_H && n == 6 + rows * ROW) {
                memcpy(image_buf + row0 * ROW, packet + 6, (size_t)(rows * ROW));
                if (row0 + rows == GFX_WINDOW_H) /* 最后一段到了, 整张换上 */
                    *image = image_buf;
            }
            continue;
        }
        if (n < HEADER || memcmp(packet, "HAND", 4) != 0)
            continue;
        uint8_t *p = packet + 4;
        raw->seq = (uint32_t)(p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24);
        raw->found = (int8_t)p[4];
        raw->fist = (int8_t)p[5];
        raw->x = (int16_t)(p[6] | p[7] << 8);
        raw->y = (int16_t)(p[8] | p[9] << 8);
        got = 1;
    }
    return got;
}
