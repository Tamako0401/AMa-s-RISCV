/* 第二个串口 (UART2) 本板接在哪。控制台串口上电就由硬件接好 (CONSOLE_UART), UART2 上电不接, 由这里接到约定的脚。
 * 程序只用 AUX_UART 和 aux_uart_init, 换脚只改这里 (同 shield_lcd.h)。
 *   mes2l100hp: GameShield 上的 WS63 星闪模块 (J5), FPGA 的 WS_TX → WS63 RXD, WS63 TXD → FPGA 的 WS_RX。
 *   mes50hp: GameShield PAD 版 (40P 排线连 J8, 针号和扩展板 J1 一样), WS_TX = J8_19, WS_RX = J8_20。
 *   其他板没有约定的接法: 不接脚, aux_uart_init 只设波特率 (收不到也发不出去)。
 * 只有头文件: 不用改 ama / build-board.py 的源文件列表. */
#ifndef AUX_UART_H
#define AUX_UART_H

#include "bsp.h"
#include "io.h"
#include "uart.h"

#define AUX_UART UART2

#ifdef BOARD_MES2L100HP
#define AUX_UART_TX_PIN PIN_WS_TX
#define AUX_UART_RX_PIN PIN_WS_RX
#endif
#ifdef BOARD_MES50HP
#define AUX_UART_TX_PIN PIN_J8_19
#define AUX_UART_RX_PIN PIN_J8_20
#endif

/* 接好脚并打开收发。写成 inline 的原因同 uart_init: baud 是常量时编译期算出分频 */
static inline void aux_uart_init(uint32_t baud)
{
#ifdef AUX_UART_TX_PIN
    io_connect_out(AUX_UART_TX_PIN, SIG_UART2_TX);
    io_connect_in(SIG_UART2_RX, AUX_UART_RX_PIN);
#endif
    uart_init(AUX_UART, SYSCLK_HZ, baud);
}

#endif
