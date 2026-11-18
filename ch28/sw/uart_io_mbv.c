/* 28장 AXI UART Lite 직접 접근 (PG142: RX FIFO 0x00, TX FIFO 0x04, STAT 0x08 — bit0 RX 있음, bit3 TX 가득) */
#include "uart_io.h"
#include "xil_io.h"

#ifndef UART_BASE
#define UART_BASE 0x40600000u   /* ⚠ Vivado 기본값. xparameters.h의 UART Lite 기준 주소로 바꾼다 */
#endif

int uart_getc(void)
{
    if ((Xil_In32(UART_BASE + 0x08u) & 0x01u) == 0u) return -1;
    return (int)(Xil_In32(UART_BASE + 0x00u) & 0xFFu);
}

void uart_puts(const char *s)
{
    while (*s) {
        while (Xil_In32(UART_BASE + 0x08u) & 0x08u) { }
        Xil_Out32(UART_BASE + 0x04u, (uint8_t)*s++);
    }
}
