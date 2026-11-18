/* 27장 PC 시험: led_word가 표시기 약속([9:0] 원핫, [13:10] 번호, [14] 오류, [15] 결과)과 같은지 */
#include <stdio.h>
#include "board_io.h"
int main(void)
{
    int fails = 0;
    for (uint32_t c = 0; c < 10; c++)
        if (led_word(c, 0) != (0x8000u | (c << 10) | (1u << c))) { printf("  FAIL class %u\n", c); fails++; }
    if (led_word(3, 1) != 0x4000u) { printf("  FAIL error word\n"); fails++; }
    printf(fails ? "LED_WORD_TEST_FAIL\n" : "LED_WORD_TEST_PASS words=11\n");
    return fails != 0;
}
