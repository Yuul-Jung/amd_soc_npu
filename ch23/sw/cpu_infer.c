/* 23장 CPU 기준 추론 (RV32IMC: 곱은 MUL, 누산은 32비트 — |점수| < 2^25이므로 넘치지 않음) */
#include "cpu_infer.h"

uint32_t cpu_infer(const int8_t w[10][784], const int32_t b[10], const uint8_t x[784], int32_t score[10])
{
    uint32_t best = 0;
    for (uint32_t c = 0; c < 10; c++) {
        int32_t acc = 0;
        for (uint32_t i = 0; i < 784; i++)
            acc += (int32_t)w[c][i] * (int32_t)x[i];
        score[c] = acc + b[c];
        if (score[c] > score[best]) best = c;     /* 같으면 앞 번호 유지 */
    }
    return best;
}
