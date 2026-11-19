/* (추가) 29장: MicroBlaze V 플랫폼 경계. (변경) 안 A: 21장 SoC(Bitstream·XSA) 그대로: AXI UART Lite 폴링,
 * AXI GPIO 0 채널 1 = LED[15:0], 표시 워드 → 표준 7세그먼트 IP(ip06_seg7, AXI GPIO 1·p3_fnd_scan 대체).
 * 시간 제한은 폴링 횟수다(실제 시간은 빌드 최적화에 따라 다르므로 보드에서 측정해 기록한다).
 */
#include "xparameters.h"
#include "xil_io.h"
#include "xuartlite_l.h"
#include "p3_seg7.h"
#include "sensor_io.h"

#ifndef SENSOR_RX_POLLS
#define SENSOR_RX_POLLS   3000000u    /* 프레임 도중 바이트 간격 제한(28장과 같은 값) */
#endif
#ifndef SENSOR_LINK_POLLS
#define SENSOR_LINK_POLLS 10000000u   /* 링크 감시: 프레임 시작 대기 제한(폴링 횟수) */
#endif
#define UART_BASE XPAR_AXI_UARTLITE_0_BASEADDR
#define LED_GPIO  XPAR_AXI_GPIO_0_BASEADDR

int sio_getc(int mode)
{
    uint32_t n = 0, limit = mode == SIO_WAIT_LINK ? SENSOR_LINK_POLLS : SENSOR_RX_POLLS;
    while (XUartLite_IsReceiveEmpty(UART_BASE)) {
        if (++n >= limit)
            return SIO_TIMEOUT;
    }
    return (int)(XUartLite_ReadReg(UART_BASE, XUL_RX_FIFO_OFFSET) & 0xFFu);
}

void sio_display(uint32_t fnd_word, uint32_t led)
{
    p3_seg7_write(p3_seg7_from_fnd_word(fnd_word));   /* (변경) 안 A: 표준 7세그먼트 IP */
    Xil_Out32(LED_GPIO, led);
}

void sio_flush(void) {}
