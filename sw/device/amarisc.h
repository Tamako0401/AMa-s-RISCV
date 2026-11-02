/* AMa-s-RISCV 外设寄存器定义
 * 地址与 rtl/soc_top/soc_top.v 一致, 位定义见 docs/spi.md. */
#ifndef AMARISC_H
#define AMARISC_H

#include <stdint.h>

#define __I volatile const /* 只读 */
#define __O volatile       /* 只写 */
#define __IO volatile      /* 读写 */

/* ---------------- SPI: STM32 风格的 8 位主机子集 ---------------- */
typedef struct {
    __IO uint32_t CR1; /* 0x00 配置 */
    __IO uint32_t CR2; /* 0x04 预留, 读零 */
    __I uint32_t SR;   /* 0x08 状态 */
    __IO uint32_t DR;  /* 0x0C 写: 送入发送缓冲; 读: 取接收缓冲并清 RXNE */
} SPI_TypeDef;

#define SPI_CR1_CPHA_Pos 0U /* 0: 前沿采样, 1: 后沿采样 */
#define SPI_CR1_CPHA_Msk (0x1UL << SPI_CR1_CPHA_Pos)
#define SPI_CR1_CPHA SPI_CR1_CPHA_Msk
#define SPI_CR1_CPOL_Pos 1U /* SCK 空闲电平 */
#define SPI_CR1_CPOL_Msk (0x1UL << SPI_CR1_CPOL_Pos)
#define SPI_CR1_CPOL SPI_CR1_CPOL_Msk
#define SPI_CR1_MSTR_Pos 2U /* 只实现主机, 固定为 1 */
#define SPI_CR1_MSTR_Msk (0x1UL << SPI_CR1_MSTR_Pos)
#define SPI_CR1_MSTR SPI_CR1_MSTR_Msk
#define SPI_CR1_BR_Pos 3U /* SCK = clk / 2^(BR+1) */
#define SPI_CR1_BR_Msk (0x7UL << SPI_CR1_BR_Pos)
#define SPI_CR1_BR SPI_CR1_BR_Msk
#define SPI_CR1_SPE_Pos 6U /* 使能 */
#define SPI_CR1_SPE_Msk (0x1UL << SPI_CR1_SPE_Pos)
#define SPI_CR1_SPE SPI_CR1_SPE_Msk

#define SPI_SR_RXNE_Pos 0U /* 接收缓冲非空 */
#define SPI_SR_RXNE_Msk (0x1UL << SPI_SR_RXNE_Pos)
#define SPI_SR_RXNE SPI_SR_RXNE_Msk
#define SPI_SR_TXE_Pos 1U /* 发送缓冲空, 可写下一字节 */
#define SPI_SR_TXE_Msk (0x1UL << SPI_SR_TXE_Pos)
#define SPI_SR_TXE SPI_SR_TXE_Msk
#define SPI_SR_OVR_Pos 6U /* 接收溢出 */
#define SPI_SR_OVR_Msk (0x1UL << SPI_SR_OVR_Pos)
#define SPI_SR_OVR SPI_SR_OVR_Msk
#define SPI_SR_BSY_Pos 7U /* 正在移位或有待发字节 */
#define SPI_SR_BSY_Msk (0x1UL << SPI_SR_BSY_Pos)
#define SPI_SR_BSY SPI_SR_BSY_Msk

/* ---------------- UART: 8N1, 接收 16 字节 FIFO ---------------- */
typedef struct {
    __IO uint32_t CTRL;   /* 0x00 bit0 发送使能, bit1 接收使能 */
    __IO uint32_t STATUS; /* 0x04 bit0 正在发送; bit1 接收 FIFO 非空 (写 0 取走一个字节) */
    __IO uint32_t BAUD;   /* 0x08 分频: 波特率 = clk / (BAUD + 1) */
    __O uint32_t TXDATA;  /* 0x0C 写入即开始发送 */
    __I uint32_t RXDATA;  /* 0x10 FIFO 里最早的字节 (空时是最后收到的) */
} UART_TypeDef;

#define UART_CTRL_TXEN (0x1UL << 0)
#define UART_CTRL_RXEN (0x1UL << 1)
#define UART_STATUS_TXBUSY (0x1UL << 0)
#define UART_STATUS_RXDONE (0x1UL << 1)

/* ---------------- GPIO 矩阵 ---------------- */
typedef struct {
    __IO uint32_t OUT[4];
    __O uint32_t OUT_W1TS[4];
    __O uint32_t OUT_W1TC[4];
    __IO uint32_t ENABLE[4];
    __O uint32_t ENABLE_W1TS[4];
    __O uint32_t ENABLE_W1TC[4];
    __I uint32_t IN[4];
    uint32_t reserved[100];
    __IO uint32_t FUNC_OUT_SEL[128];
    __IO uint32_t FUNC_IN_SEL[4]; /* 3 号保留 */
} IO_TypeDef;

#define IO_MATRIX ((IO_TypeDef *)0x40003000UL)

/* ---------------- 视频: 640x480 输出, 画面 320x240 (每点 2x2), 见 docs/video.md ---------------- */
typedef struct {
    __IO uint32_t CTRL;   /* 0x00 bit0 开显示 (关时输出黑屏), bit1 开小窗 */
    __IO uint32_t SCROLL; /* 0x04 背景偏移: [8:0] x, [23:16] y */
    __I uint32_t STATUS;  /* 0x08 bit0 场消隐期 */
    __I uint32_t FRAME;   /* 0x0C 帧计数, 每帧最后一行显示完加 1 */
    __IO uint32_t WINDOW; /* 0x10 小窗 (160x120, 显示视觉输入) 左上角: [8:0] x, [23:16] y */
} VIDEO_TypeDef;

#define VIDEO_CTRL_EN (0x1UL << 0)
#define VIDEO_CTRL_WINDOW (0x1UL << 1)
#define VIDEO_STATUS_VBLANK (0x1UL << 0)

/* 显存只能整字写, 读回 0 */
#define VIDEO_PALETTE ((__O uint32_t *)0x20001000UL) /* [256] RGB565, 下标 = 调色板号 * 16 + 色号 */
#define VIDEO_SPRITES ((__O uint32_t *)0x20002000UL) /* [64] 属性, 见 VIDEO_SPRITE() */
#define VIDEO_MAP ((__O uint32_t *)0x20004000UL)     /* [32 行][64 列] {调色板号[11:8], 图块号[7:0]} */
#define VIDEO_TILES ((__O uint32_t *)0x20008000UL)   /* [256 块][8 行], 左起第 i 个像素在 [4i+3:4i] */

/* 精灵属性: 16x16, 由图块 tile ~ tile+3 拼成 (左上、右上、左下、右下); x、y 按 512 回绕, 可以半出屏 */
#define VIDEO_SPRITE(x, y, tile, pal)                                                                                  \
    ((1UL << 31) | ((uint32_t)(pal) << 26) | ((uint32_t)(tile) << 18) | (((uint32_t)(y) & 511) << 9) |                 \
     ((uint32_t)(x) & 511))

/* ---------------- 视觉输入: 颜色跟踪, 见 docs/vision.md ---------------- */
typedef struct {
    __IO uint32_t COLOR; /* 0x00 目标颜色和容差: [7:0] Cb, [15:8] Cr, [23:16] 容差 */
    __I uint32_t COUNT;  /* 0x04 上一帧命中的点数 (160x120 里) */
    __I uint32_t SUM_X;  /* 0x08 命中点的 x 之和 */
    __I uint32_t SUM_Y;  /* 0x0C 命中点的 y 之和 */
    __I uint32_t FRAME;  /* 0x10 每出一帧结果加 1 */
    __I uint32_t CENTER; /* 0x14 画面正中 8x8 的平均颜色: [7:0] Cb, [15:8] Cr (标定用) */
    __I uint32_t INPUT_SIZE;   /* 0x18 [11:0] 有效宽, [27:16] 有效高 */
    __I uint32_t INPUT_STATUS; /* 0x1C bit0 支持, bit1 尺寸稳定, bit2 不支持/坏帧 */
} VISION_TypeDef;

/* ---------------- handnet 加速器: 寄存器见 docs/nn.md ---------------- */
typedef struct {
    __IO uint32_t CTRL;     /* 0x00 bit0 写 1 开始一次推理; bit1 写 1 清 DONE */
    __I uint32_t STATUS;    /* 0x04 bit0 忙, bit1 完成, [7:4] 当前层号 */
    __O uint32_t IN;        /* 0x08 写一个像素 {8'b0, R, G, B}, 像素地址自增 */
    __IO uint32_t IN_ADDR;  /* 0x0C 下一个要写的像素 */
    __IO uint32_t OUT_ADDR; /* 0x10 要读的输出字 (格子号) */
    __I uint32_t OUT;       /* 0x14 {握拳, dy, dx, 热力图} 的 int8 logit, 低字节是热力图 */
    __I uint32_t CYCLE;     /* 0x18 上一次推理用了多少拍 */
    __I uint32_t VERSION;   /* 0x1C 0x4e4e_0001 */
    __I uint32_t IN_PIX;    /* 0x20 输入像素个数 */
} NN_TypeDef;

#define NN_CTRL_START (0x1UL << 0)
#define NN_CTRL_CLEAR (0x1UL << 1)
#define NN_STATUS_BUSY (0x1UL << 0)
#define NN_STATUS_DONE (0x1UL << 1)
#define NN_STATUS_LAYER_Pos 4U

/* ---------------- 基址 ---------------- */
#define SPI1_BASE 0x40002000UL
#define UART1_BASE 0x40001000UL
#define UART2_BASE 0x40007000UL
#define VIDEO_BASE 0x20000000UL
#define VISION_BASE 0x40005000UL
#define NN_BASE 0x40006000UL

#define SPI1 ((SPI_TypeDef *)SPI1_BASE)
#define UART1 ((UART_TypeDef *)UART1_BASE)
#define UART2 ((UART_TypeDef *)UART2_BASE) /* 第二个串口, 收发脚上电不接, 见 bsp.h 的 AUX_UART */
#define VIDEO ((VIDEO_TypeDef *)VIDEO_BASE)
#define VISION ((VISION_TypeDef *)VISION_BASE)
#define NN ((NN_TypeDef *)NN_BASE)

#endif
