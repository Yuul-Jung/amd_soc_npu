/* 22장 Vitis 애플리케이션: 18장 실제 MNIST INT8 모델과 시험 5장으로 NPU 추론, UART로 점수·클래스 출력 */
#include "npu_drv.h"
#include "model_int8.h"
#ifdef NPU_HOST
#include <stdio.h>
#define PRINT printf
#else
#include "xil_printf.h"
#define PRINT xil_printf
#endif

#define POLL_LIMIT 100000u        /* 추론 7,185클록 동안 STATUS 읽기는 수백 번 → 넉넉한 상한 */

int main(void)
{
    npu_result_t r;
    PRINT("=== ch22 NPU driver (MNIST INT8 784x10) ===\r\n");
    if (npu_init() != NPU_OK) { PRINT("[FAIL] NPU ID mismatch\r\n"); return 1; }
    npu_load_model(MODEL_W, MODEL_B);
    int right = 0;
    for (int n = 0; n < TEST_N; n++) {
        npu_status_t s = npu_load_input(TEST_X[n]);
        if (s == NPU_OK) s = npu_run(&r, POLL_LIMIT);
        if (s != NPU_OK) { PRINT("[FAIL] image %d status %d\r\n", n, (int)s); return 1; }
        PRINT("image %d label %d class %d cycles %d score", n, (int)TEST_LABEL[n], (int)r.cls, (int)r.cycles);
        for (int k = 0; k < NPU_N_OUT; k++) PRINT(" %d", (int)r.score[k]);
        PRINT("\r\n");
        right += (r.cls == (uint32_t)TEST_LABEL[n]);
    }
    PRINT("[PASS] %d/%d correct\r\n", right, TEST_N);
    return 0;
}
