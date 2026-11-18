/* 28장 UART 한 바이트 입출력 (보드: AXI UART Lite 레지스터, PC: 표준 입출력) */
#ifndef UART_IO_H
#define UART_IO_H
#include <stdint.h>
int  uart_getc(void);          /* 받은 바이트 0~255, 없으면 -1 (PC: 입력 끝이면 -2) */
void uart_puts(const char *s);
#endif
