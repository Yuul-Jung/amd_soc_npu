/* 27장 PC 시험용 GPIO: 스위치는 0,1,…,9,12 순서로 바꾸고, LED 쓰기는 기록 파일에 'G 값'으로 남긴다. */
#include <stdio.h>
#include <stdlib.h>
#include "board_io.h"

uint32_t host_steps = 11;
static const uint32_t seq[11] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 12};
static int pos = -1;

uint32_t sw_read(void) { return seq[++pos % 11]; }

void led_write(uint32_t v)
{
    const char *p = getenv("LED_LOG");
    FILE *fp = p ? fopen(p, "a") : NULL;
    if (fp) { fprintf(fp, "%u %u\n", seq[pos % 11], v); fclose(fp); }
}
