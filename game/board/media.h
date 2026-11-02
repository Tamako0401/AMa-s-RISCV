#ifndef BOARD_MEDIA_H
#define BOARD_MEDIA_H
/* 上电读 SD/FAT/PAK; 返回 1 成功, 无卡失败后本次启动不再重试。 */
int media_init(void);
#endif
