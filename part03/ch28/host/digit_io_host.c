/* (추가) 28장: PC 협동 시뮬레이션 플랫폼 경계. 표준 입력 = UART 수신(PC 호스트 도구가 파이프로 프레임을 보냄),
 * 표준 출력 = UART 송신. 바이트 간격 제한은 poll()의 밀리초 제한으로 흉내 낸다. 표시 값은 DISP 줄로만 확인한다.
 */
#include <poll.h>
#include <stdio.h>
#include <unistd.h>
#include "digit_io.h"

#ifndef DIGIT_HOST_TIMEOUT_MS
#define DIGIT_HOST_TIMEOUT_MS 300
#endif

int dio_getc(int wait_forever)
{
    struct pollfd pfd = {0, POLLIN, 0};
    unsigned char ch;
    int r = poll(&pfd, 1, wait_forever ? -1 : DIGIT_HOST_TIMEOUT_MS);
    if (r == 0)
        return DIO_TIMEOUT;
    if (r < 0 || read(0, &ch, 1) != 1)
        return DIO_EOF;
    return ch;
}

void dio_display(uint32_t fnd_word, uint32_t led)
{
    (void)fnd_word;
    (void)led;
}

void dio_flush(void) { fflush(stdout); }
