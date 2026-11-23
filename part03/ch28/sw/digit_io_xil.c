/* MicroBlaze V 플랫폼 경계. AXI UART Lite(stdin/stdout과 같은 장치) 폴링 수신,
 * AXI GPIO 0 채널 1 = LED[15:0], 표시 워드 → 표준 7세그먼트 IP(ip06_seg7). AXI GPIO 1·p3_fnd_scan은 쓰지 않는다.
 */
#include "xparameters.h"
#include "xil_io.h"
#include "xuartlite_l.h"
#include "p3_seg7.h"
#include "digit_io.h"

#ifndef DIGIT_RX_POLLS
#define DIGIT_RX_POLLS 3000000u   /* 프레임 도중 바이트 간격 제한(폴링 횟수, 100 MHz -O0에서 약 1초 이상) */
#endif
#define UART_BASE XPAR_AXI_UARTLITE_0_BASEADDR
#define LED_GPIO  XPAR_AXI_GPIO_0_BASEADDR

int dio_getc(int wait_forever)
{
    uint32_t n = 0;
    while (XUartLite_IsReceiveEmpty(UART_BASE)) {
        if (!wait_forever && ++n >= DIGIT_RX_POLLS)
            return DIO_TIMEOUT;
    }
    return (int)(XUartLite_ReadReg(UART_BASE, XUL_RX_FIFO_OFFSET) & 0xFFu);
}

void dio_display(uint32_t fnd_word, uint32_t led)
{
    p3_seg7_write(p3_seg7_from_fnd_word(fnd_word));   /* 표준 7세그먼트 IP */
    Xil_Out32(LED_GPIO, led);
}

void dio_flush(void) {}
