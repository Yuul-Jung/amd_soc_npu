/* 22장 NPU 드라이버: 모델·입력 적재, 시작, 완료 대기(시간 제한), 결과 읽기 */
#ifndef NPU_DRV_H
#define NPU_DRV_H
#include <stdint.h>
#include "npu_regs.h"

typedef enum {
    NPU_OK = 0,
    NPU_ERR_ID = -1,        /* ID 레지스터가 0x4E505531이 아님 (주소·비트스트림 확인) */
    NPU_ERR_BUSY = -2,      /* 이미 실행 중 */
    NPU_ERR_TIMEOUT = -3,   /* 시간 제한 안에 DONE·ERROR가 오지 않음 */
    NPU_ERR_HW = -4         /* STATUS.ERROR */
} npu_status_t;

typedef struct {
    int32_t  score[NPU_N_OUT];
    uint32_t cls;
    uint32_t cycles;
} npu_result_t;

npu_status_t npu_init(void);
void         npu_load_model(const int8_t w[NPU_N_OUT][NPU_N_IN], const int32_t b[NPU_N_OUT]);
npu_status_t npu_load_input(const uint8_t x[NPU_N_IN]);
npu_status_t npu_run(npu_result_t *out, uint32_t poll_limit);

#endif
