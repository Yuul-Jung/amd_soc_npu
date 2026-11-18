/* 27장 최종 시스템: 스위치 sw[3:0]로 고른 숫자 그림(실제 MNIST 시험 그림, 숫자마다 1장)을 NPU로 분류해
 * UART에 점수 10개·클래스·클록을 찍고, LED에 원핫·번호, 7세그먼트 오른쪽 자리에 클래스를 보인다.
 * sw[3:0]가 10 이상이면 표시를 '-'로 지운다. */
#include "npu_drv.h"
#include "board_io.h"
#include "model_int8.h"
#ifdef NPU_HOST
#include <stdio.h>
#define PRINT printf
extern uint32_t host_steps;              /* PC 시험: 스위치 값을 차례로 바꿔 보는 횟수 */
#else
#include "xil_printf.h"
#define PRINT xil_printf
#endif

static void show(uint32_t idx)
{
    npu_result_t r;
    if (idx >= TEST_N) { led_write(0); PRINT("sw=%d: no image\r\n", (int)idx); return; }
    npu_status_t s = npu_load_input(TEST_X[idx]);
    if (s == NPU_OK) s = npu_run(&r, 100000u);
    if (s != NPU_OK) { led_write(led_word(0, 1)); PRINT("sw=%d: NPU error %d\r\n", (int)idx, (int)s); return; }
    led_write(led_word(r.cls, 0));
    PRINT("sw=%d label=%d class=%d cycles=%d score", (int)idx, (int)TEST_LABEL[idx], (int)r.cls, (int)r.cycles);
    for (int k = 0; k < NPU_N_OUT; k++) PRINT(" %d", (int)r.score[k]);
    PRINT(" %s\r\n", r.cls == TEST_LABEL[idx] ? "OK" : "MISS");
}

int main(void)
{
    PRINT("=== ch27 NPU SoC (MNIST INT8 784x10, sw[3:0] = digit image) ===\r\n");
    if (npu_init() != NPU_OK) { led_write(led_word(0, 1)); PRINT("[FAIL] NPU ID\r\n"); return 1; }
    npu_load_model(MODEL_W, MODEL_B);
    uint32_t last = 0xFFFFFFFFu;
#ifdef NPU_HOST
    while (host_steps--) {
#else
    for (;;) {
#endif
        uint32_t idx = sw_read() & 0xFu;
        if (idx != last) { show(idx); last = idx; }
    }
    return 0;
}
