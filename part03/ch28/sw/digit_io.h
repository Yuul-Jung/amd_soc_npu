/* 숫자 인식 응용의 플랫폼 경계. 같은 digit_app.c를 MicroBlaze V와 PC 시뮬레이션이 함께 쓴다.
 *   MicroBlaze V: digit_io_xil.c (AXI UART Lite 폴링 수신, AXI GPIO 0 = LED, AXI GPIO 1 = FND 표시 워드)
 *   PC          : host/digit_io_host.c (표준 입력 = UART 수신, 표시 값은 DISP 줄로만 확인)
 */
#ifndef DIGIT_IO_H
#define DIGIT_IO_H
#include <stdint.h>

#define DIO_TIMEOUT (-1)   /* 프레임 도중 바이트 간격 제한 초과 */
#define DIO_EOF     (-2)   /* PC 전용: 입력 종료 */

/* wait_forever = 1: 프레임 시작 대기(제한 없음), 0: 프레임 도중(바이트 간격 제한) */
int dio_getc(int wait_forever);
void dio_display(uint32_t fnd_word, uint32_t led);
void dio_flush(void);

#endif
