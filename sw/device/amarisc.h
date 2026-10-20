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

/* ---------------- UART: 8N1, 无 FIFO ---------------- */
typedef struct {
    __IO uint32_t CTRL;   /* 0x00 bit0 发送使能, bit1 接收使能 */
    __IO uint32_t STATUS; /* 0x04 bit0 正在发送; bit1 收到一字节 (写 0 清除) */
    __IO uint32_t BAUD;   /* 0x08 分频: 波特率 = clk / (BAUD + 1) */
    __O uint32_t TXDATA;  /* 0x0C 写入即开始发送 */
    __I uint32_t RXDATA;  /* 0x10 最近收到的字节 */
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
    __IO uint32_t FUNC_IN_SEL[2];
} IO_TypeDef;

#define IO_MATRIX ((IO_TypeDef *)0x40003000UL)

/* ---------------- 基址 ---------------- */
#define SPI1_BASE 0x40002000UL
#define UART1_BASE 0x40001000UL

#define SPI1 ((SPI_TypeDef *)SPI1_BASE)
#define UART1 ((UART_TypeDef *)UART1_BASE)

#endif
