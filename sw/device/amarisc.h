/* AMa-s-RISCV 外设寄存器定义
 * 地址与 rtl/soc_top/soc_top.v 一致, 位定义见 docs/spi.md. */
#ifndef AMARISC_H
#define AMARISC_H

#include <stdint.h>

#define __I  volatile const  /* 只读 */
#define __O  volatile        /* 只写 */
#define __IO volatile        /* 读写 */

/* ---------------- SPI: STM32 风格的 8 位主机子集 ---------------- */
typedef struct {
    __IO uint32_t CR1;       /* 0x00 配置 */
    __IO uint32_t CR2;       /* 0x04 预留, 读零 */
    __I  uint32_t SR;        /* 0x08 状态 */
    __IO uint32_t DR;        /* 0x0C 写: 送入发送缓冲; 读: 取接收缓冲并清 RXNE */
} SPI_TypeDef;

#define SPI_CR1_CPHA_Pos   0U    /* 0: 前沿采样, 1: 后沿采样 */
#define SPI_CR1_CPHA_Msk   (0x1UL << SPI_CR1_CPHA_Pos)
#define SPI_CR1_CPHA       SPI_CR1_CPHA_Msk
#define SPI_CR1_CPOL_Pos   1U    /* SCK 空闲电平 */
#define SPI_CR1_CPOL_Msk   (0x1UL << SPI_CR1_CPOL_Pos)
#define SPI_CR1_CPOL       SPI_CR1_CPOL_Msk
#define SPI_CR1_MSTR_Pos   2U    /* 只实现主机, 固定为 1 */
#define SPI_CR1_MSTR_Msk   (0x1UL << SPI_CR1_MSTR_Pos)
#define SPI_CR1_MSTR       SPI_CR1_MSTR_Msk
#define SPI_CR1_BR_Pos     3U    /* SCK = clk / 2^(BR+1) */
#define SPI_CR1_BR_Msk     (0x7UL << SPI_CR1_BR_Pos)
#define SPI_CR1_BR         SPI_CR1_BR_Msk
#define SPI_CR1_SPE_Pos    6U    /* 使能 */
#define SPI_CR1_SPE_Msk    (0x1UL << SPI_CR1_SPE_Pos)
#define SPI_CR1_SPE        SPI_CR1_SPE_Msk

#define SPI_SR_RXNE_Pos    0U    /* 接收缓冲非空 */
#define SPI_SR_RXNE_Msk    (0x1UL << SPI_SR_RXNE_Pos)
#define SPI_SR_RXNE        SPI_SR_RXNE_Msk
#define SPI_SR_TXE_Pos     1U    /* 发送缓冲空, 可写下一字节 */
#define SPI_SR_TXE_Msk     (0x1UL << SPI_SR_TXE_Pos)
#define SPI_SR_TXE         SPI_SR_TXE_Msk
#define SPI_SR_OVR_Pos     6U    /* 接收溢出 */
#define SPI_SR_OVR_Msk     (0x1UL << SPI_SR_OVR_Pos)
#define SPI_SR_OVR         SPI_SR_OVR_Msk
#define SPI_SR_BSY_Pos     7U    /* 正在移位或有待发字节 */
#define SPI_SR_BSY_Msk     (0x1UL << SPI_SR_BSY_Pos)
#define SPI_SR_BSY         SPI_SR_BSY_Msk

/* ---------------- GPIO: CTRL 编码不是 STM32 MODER ---------------- */
typedef struct {
    __IO uint32_t CTRL;      /* 0x00 每引脚 2 位, 取值见 GPIO_MODE_* */
    __IO uint32_t DATA;      /* 0x04 输出数据 / 输入采样 */
    __O  uint32_t BSRR;      /* 0x08 低 16 位写 1 置位, 高 16 位写 1 清零; 读为 0 */
} GPIO_TypeDef;

#define GPIO_MODE_HIZ      0x0UL
#define GPIO_MODE_OUTPUT   0x1UL
#define GPIO_MODE_INPUT    0x2UL

/* ---------------- 基址 ---------------- */
#define SPI1_BASE   0x40002000UL
#define GPIO_BASE   0x40000000UL

#define SPI1        ((SPI_TypeDef *)SPI1_BASE)
#define GPIO        ((GPIO_TypeDef *)GPIO_BASE)

#endif
