/* 23장 CPU·NPU 시간 비교: 같은 모델·같은 5장으로 CPU 추론, NPU 입력 적재, NPU 실행을 AXI Timer로 잰다.
 * 출력은 CSV 한 줄씩: image,label,cpu_class,npu_class,cpu_clk,npu_load_clk,npu_run_clk,npu_core_clk */
#include "cpu_infer.h"
#include "npu_drv.h"
#include "axi_timer.h"
#include "model_int8.h"
#include "xil_printf.h"

int main(void)
{
    int32_t s[10];
    npu_result_t r;
    xil_printf("=== ch23 CPU vs NPU (MNIST INT8 784x10, 100 MHz) ===\r\n");
    if (npu_init() != NPU_OK) { xil_printf("[FAIL] NPU ID\r\n"); return 1; }
    npu_load_model(MODEL_W, MODEL_B);
    timer_start();
    xil_printf("image,label,cpu_class,npu_class,cpu_clk,npu_load_clk,npu_run_clk,npu_core_clk\r\n");
    int same = 0;
    for (int n = 0; n < TEST_N; n++) {
        uint32_t t0 = timer_now();
        uint32_t cc = cpu_infer(MODEL_W, MODEL_B, TEST_X[n], s);
        uint32_t t1 = timer_now();
        if (npu_load_input(TEST_X[n]) != NPU_OK) return 1;
        uint32_t t2 = timer_now();
        if (npu_run(&r, 100000u) != NPU_OK) return 1;
        uint32_t t3 = timer_now();
        int eq = (cc == r.cls);
        for (int k = 0; k < 10; k++) eq &= (s[k] == r.score[k]);
        same += eq;
        xil_printf("%d,%d,%d,%d,%d,%d,%d,%d\r\n", n, (int)TEST_LABEL[n], (int)cc, (int)r.cls,
                   (int)(t1 - t0), (int)(t2 - t1), (int)(t3 - t2), (int)r.cycles);
    }
    xil_printf("[%s] CPU and NPU scores equal %d/%d\r\n", same == TEST_N ? "PASS" : "FAIL", same, TEST_N);
    return 0;
}
