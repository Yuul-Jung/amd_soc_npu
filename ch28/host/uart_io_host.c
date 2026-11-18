/* 28장 PC 시험용 UART: 받는 바이트는 표준 입력, 보내는 글자는 표준 출력 */
#include <stdio.h>
#include "uart_io.h"
int uart_getc(void) { int c = getchar(); return c == EOF ? -2 : c; }
void uart_puts(const char *s) { fputs(s, stdout); }
