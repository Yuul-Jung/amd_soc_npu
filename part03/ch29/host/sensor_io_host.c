/* PC 시뮬레이션 플랫폼 경계. 표준 입력 = UART 수신, 표준 출력 = UART 송신.
 * 시간 제한은 poll()의 밀리초 제한으로 흉내 낸다. 표시 값은 DISP 줄로만 확인한다.
 */
#include <poll.h>
#include <stdio.h>
#include <unistd.h>
#include "sensor_io.h"

#ifndef SENSOR_HOST_BYTE_MS
#define SENSOR_HOST_BYTE_MS 300
#endif
#ifndef SENSOR_HOST_LINK_MS
#define SENSOR_HOST_LINK_MS 1500
#endif

int sio_getc(int mode)
{
    struct pollfd pfd = {0, POLLIN, 0};
    unsigned char ch;
    int r = poll(&pfd, 1, mode == SIO_WAIT_LINK ? SENSOR_HOST_LINK_MS : SENSOR_HOST_BYTE_MS);
    if (r == 0)
        return SIO_TIMEOUT;
    if (r < 0 || read(0, &ch, 1) != 1)
        return SIO_EOF;
    return ch;
}

void sio_display(uint32_t fnd_word, uint32_t led)
{
    (void)fnd_word;
    (void)led;
}

void sio_flush(void) { fflush(stdout); }
