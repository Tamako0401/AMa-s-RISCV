#ifndef SD_H
#define SD_H
#include <stdint.h>
/* 返回 1 成功, 0 超时/协议错误。只读; sd_init 返回 1=SDSC, 2=SDHC。 */
int sd_init(void);
int sd_read_block(uint32_t lba, uint8_t data[512]);
#endif
