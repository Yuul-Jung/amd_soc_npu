/* (추가) 23장: 같은 MicroBlaze V SoC에서 CPU 정수 추론과 NPU 추론의 클록 수를 AXI Timer로 잰다.
 * 측정 구간
 *   CPU      : cpu_infer() 784×10 MAC + Bias + argmax (22장 드라이버와 같은 C, 소프트웨어 곱셈)
 *   NPU_BIAS : npu_set_bias() (모델 적재 1회분, 추론마다 반복하지 않아도 됨)
 *   NPU      : npu_infer() 타일 13개의 W·X 레지스터 쓰기 + TILE_GO + 폴링 + 점수 읽기(종단간)
 * 결과는 GPIO 데이터 레지스터에 순서대로 쓴다(시뮬레이션 TB가 AXI 쓰기를 기록). 보드용은 UART로도 출력.
 * 순서: 0xBE0C0001, CPU, NPU_BIAS, NPU, cpu_class, npu_class, scores_match, rc, 0xBE0C00FF
 */
#include "xparameters.h"
#include "xil_io.h"
#include "npu_driver.h"
#include "model_data.h"
#include "bench_cfg.h"
#if !BENCH_SIM
#include "xil_printf.h"
#endif

#define TMR   XPAR_AXI_TIMER_0_BASEADDR
#define GPIO  XPAR_AXI_GPIO_0_BASEADDR
#define TCSR0 0x00u
#define TLR0  0x04u
#define TCR0  0x08u

static void tmr_start(void)
{
    Xil_Out32(TMR + TLR0, 0);
    Xil_Out32(TMR + TCSR0, 1u << 5);                 /* LOAD0: TLR0 → TCR0 */
    Xil_Out32(TMR + TCSR0, (1u << 7) | (1u << 4));   /* ENT0 + ARHT0: 위로 세는 자유 카운터 */
}

static uint32_t tmr_now(void) { return Xil_In32(TMR + TCR0); }

static void report(uint32_t v) { Xil_Out32(GPIO, v); }

int main(void)
{
    npu_t npu;
    int64_t cs[NPU_N_CLASS], ns[NPU_N_CLASS];
    int ccls, ncls = -1, rc, c, same = 1;
    uint32_t t0, t_cpu, t_bias, t_npu, t_empty;

    tmr_start();
    report(0xBE0C0001u);
    t0 = tmr_now();
    t_empty = tmr_now() - t0;                        /* 측정 자체 비용 */
    t0 = tmr_now();
    ccls = cpu_infer(sample_x[0], model_w, model_b, cs);
    t_cpu = tmr_now() - t0 - t_empty;
    npu_init(&npu, XPAR_P3_NPU_0_BASEADDR);
    t0 = tmr_now();
    rc = npu_set_bias(&npu, model_b);
    t_bias = tmr_now() - t0 - t_empty;
    t0 = tmr_now();
    rc |= npu_infer(&npu, sample_x[0], model_w, ns, &ncls);
    t_npu = tmr_now() - t0 - t_empty;
    for (c = 0; c < NPU_N_CLASS; c++)
        if (ns[c] != cs[c] || cs[c] != sample_scores[0][c])
            same = 0;
    report(t_cpu);
    report(t_bias);
    report(t_npu);
    report((uint32_t)ccls);
    report((uint32_t)ncls);
    report((uint32_t)same);
    report((uint32_t)rc);
    report(0xBE0C00FFu);
#if !BENCH_SIM
    xil_printf("BENCH cpu_cycles=%u npu_bias_cycles=%u npu_cycles=%u cpu_class=%d npu_class=%d match=%d rc=%d\r\n",
               (unsigned)t_cpu, (unsigned)t_bias, (unsigned)t_npu, ccls, ncls, same, rc);
#endif
    return 0;
}
