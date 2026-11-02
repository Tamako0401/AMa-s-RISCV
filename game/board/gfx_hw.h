/* gfx.h 的板上版: 写新显示 (rtl/display, rib s3 0x3000_0000) 的寄存器, 地址和格式见 docs/display.md。
 * 精灵先记在内存里 (游戏拿到指针后还会改 flags 等), gfx_hw_present 时一起写进显示的后台精灵表再提交;
 * 背景图块、文字直接写, 立刻生效 (游戏本来就是 "改了才写")。 */
#ifndef GFX_HW_H
#define GFX_HW_H

#include <stdint.h>
#include "gfx.h"

#define GFX_HW_SPRITES 512 /* 硬件精灵表的容量, 多的不画 */

/* 开机一次: 关显示, 写调色板、图案表、图案库、字库 (refmodel.py firmware 生成的 display_assets.c, 压缩的开机解压), 清背景和文字 */
void gfx_hw_init(void);
/* 一帧画完: 等上一帧换上去, 写精灵表和寄存器, 提交 (下一个场消隐生效, 所以自然是 60 帧/秒) */
void gfx_hw_present(void);
/* 显示的统计: 上一帧最忙一行的拍数 (共约 2222)、累计没画完的行、累计丢掉的对象 */
uint32_t gfx_hw_line_max(void);
uint32_t gfx_hw_overrun(void);
uint32_t gfx_hw_dropped(void);
/* 显示出了几帧 (每帧 +1, 60 帧/秒) */
uint32_t gfx_hw_frame(void);

#endif
