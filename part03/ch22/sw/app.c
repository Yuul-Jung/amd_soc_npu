/* NPU 추론 응용. MicroBlaze V(main.c)와 PC 시뮬레이션(host/cosim_main.c)이 같은 코드를 쓴다.
 * 표본마다 NPU 추론과 CPU 정수 추론을 실행해 10개 점수·Class를 서로, 그리고 4-3 평가 기대값과 비교한다.
 */
#include "app.h"
#include "npu_driver.h"
#include "model_data.h"

int app_run(uintptr_t npu_base)
{
    npu_t npu;
    int s, c, rc, failures = 0;
    npu_init(&npu, npu_base);
    rc = npu_set_bias(&npu, model_b);
    if (rc != NPU_OK) {
        APP_PRINTF("NPU_BIAS_FAIL rc=%d status=0x%08x\r\n", rc, (unsigned)npu_last_status(&npu));
        return MODEL_N_SAMPLES;
    }
    npu_irq_enable(&npu, 1);
    for (s = 0; s < MODEL_N_SAMPLES; s++) {
        int64_t ns[NPU_N_CLASS], cs[NPU_N_CLASS];
        int ncls = -1, ccls, same = 1;
        rc = npu_infer(&npu, sample_x[s], model_w, ns, &ncls);
        ccls = cpu_infer(sample_x[s], model_w, model_b, cs);
        for (c = 0; c < NPU_N_CLASS; c++)
            if (ns[c] != cs[c] || ns[c] != sample_scores[s][c])
                same = 0;
        if (rc != NPU_OK || !same || ncls != ccls || ncls != sample_class[s])
            failures++;
        APP_PRINTF("SAMPLE %d index=%d label=%d npu_class=%d cpu_class=%d expect=%d scores_match=%d rc=%d\r\n",
                   s, sample_index[s], sample_label[s], ncls, ccls, sample_class[s], same, rc);
        app_show(s, ncls);   /* LED·7세그먼트 표시 */
        npu_clear_done(&npu);
    }
    APP_PRINTF("NPU_APP_DONE samples=%d failures=%d\r\n", MODEL_N_SAMPLES, failures);
    return failures;
}
