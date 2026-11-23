/* 센서 감시 응용의 플랫폼 경계(6-1 digit_io.h와 같은 구조, 대기 방식만 다르다).
 *   MicroBlaze V: sensor_io_xil.c (AXI UART Lite 폴링, AXI GPIO 0 = LED, AXI GPIO 1 = FND 표시 워드) — 6-1 Bitstream 그대로
 *   PC          : host/sensor_io_host.c (표준 입력 = UART 수신)
 */
#ifndef SENSOR_IO_H
#define SENSOR_IO_H
#include <stdint.h>

#define SIO_TIMEOUT (-1)   /* 제한 시간 동안 바이트 없음 */
#define SIO_EOF     (-2)   /* PC 전용: 입력 종료 */

#define SIO_WAIT_LINK  1   /* 프레임 시작 대기: 링크 감시 시간(센서 프레임이 이보다 오래 없으면 UNKNOWN) */
#define SIO_IN_FRAME   0   /* 프레임 도중: 바이트 간격 제한 */

int sio_getc(int mode);
void sio_display(uint32_t fnd_word, uint32_t led);
void sio_flush(void);

#endif
