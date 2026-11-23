/* 5-1 AXI4-Lite NPU 제어 IP(p3_npu_axi_lite) C 드라이버.
 * 레지스터 접근은 npu_io_read/npu_io_write 두 함수로만 한다.
 *   Vitis(MicroBlaze V): Xil_In32/Xil_Out32 (npu_io_xil.c)
 *   PC 시뮬레이션: FIFO로 RTL에 전달 (host/npu_io_cosim.c)
 * 베이스 주소는 xparameters.h(Vivado Address Editor 값)에서 받는다. 드라이버에 고정하지 않는다.
 */
#ifndef NPU_DRIVER_H
#define NPU_DRIVER_H

#include <stdint.h>

#define NPU_N_IN    784
#define NPU_N_CLASS 10
#define NPU_TILE    64
#define NPU_N_TILE  13

/* 레지스터 오프셋 (5-1 docs/README.md 레지스터 맵) */
#define NPU_CTRL      0x00u
#define NPU_STATUS    0x04u
#define NPU_LENGTH    0x08u
#define NPU_CLASS     0x0Cu
#define NPU_X_INDEX   0x10u
#define NPU_X_DATA    0x14u
#define NPU_W_CLASS   0x18u
#define NPU_W_INDEX   0x1Cu
#define NPU_W_DATA    0x20u
#define NPU_BIAS_LO   0x24u
#define NPU_BIAS_HI   0x28u
#define NPU_SCORE_SEL 0x2Cu
#define NPU_SCORE_LO  0x30u
#define NPU_SCORE_HI  0x34u
#define NPU_IRQ_EN    0x38u

#define NPU_CTRL_START   0x1u
#define NPU_CTRL_TILE_GO 0x2u
#define NPU_CTRL_ABORT   0x4u

#define NPU_ST_BUSY       (1u << 0)
#define NPU_ST_DONE       (1u << 1)
#define NPU_ST_ERROR      (1u << 2)
#define NPU_ST_OVF        (1u << 3)
#define NPU_ST_LOAD_READY (1u << 4)
#define NPU_ST_X_HELD     (1u << 5)
#define NPU_ST_TILE(s)    (((s) >> 8) & 0xFu)
#define NPU_ST_ERR_CODE(s) (((s) >> 12) & 0xFu)

/* 반환 코드 */
#define NPU_OK          0
#define NPU_E_TIMEOUT  -1
#define NPU_E_HW       -2   /* STATUS.ERROR: npu_last_status()의 ERR_CODE 확인 */
#define NPU_E_OVERFLOW -3   /* STATUS.OVF: 외부 누산 넘침(41비트 계약 위반) */

typedef struct {
    uintptr_t base;
    uint32_t last_status;
    uint32_t poll_limit;    /* STATUS 폴링 최대 횟수 */
} npu_t;

uint32_t npu_io_read(uintptr_t addr);
void npu_io_write(uintptr_t addr, uint32_t value);

void npu_init(npu_t *npu, uintptr_t base);
int npu_set_bias(npu_t *npu, const int64_t bias[NPU_N_CLASS]);
/* 784 입력 전체 추론. w는 class 우선 [10][784] INT8. scores는 42비트 signed 점수. */
int npu_infer(npu_t *npu, const int8_t x[NPU_N_IN], const int8_t w[NPU_N_CLASS][NPU_N_IN],
              int64_t scores[NPU_N_CLASS], int *class_id);
void npu_irq_enable(npu_t *npu, int enable);
void npu_clear_done(npu_t *npu);
uint32_t npu_last_status(const npu_t *npu);

/* 같은 정수 연산의 CPU 기준 구현(5-4 CPU·NPU 비교에도 사용) */
int cpu_infer(const int8_t x[NPU_N_IN], const int8_t w[NPU_N_CLASS][NPU_N_IN],
              const int64_t bias[NPU_N_CLASS], int64_t scores[NPU_N_CLASS]);

#endif
