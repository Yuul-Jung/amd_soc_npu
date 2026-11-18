/* 23장 PC 시험: cpu_infer가 18장 정수 기준과 같은 점수를 내는지 시험 집합 20장으로 확인한다 (점수는 표준 출력). */
#include <stdio.h>
#include "cpu_infer.h"
#include "model_int8.h"

int main(void)
{
    int32_t s[10];
    for (int n = 0; n < TEST_N; n++) {
        uint32_t c = cpu_infer(MODEL_W, MODEL_B, TEST_X[n], s);
        printf("%d", n);
        for (int k = 0; k < 10; k++) printf(" %d", s[k]);
        printf(" %u\n", c);
    }
    return 0;
}
