/* 22장 레지스터 접근 계층. 보드: npu_hal_mbv.c (Xil_In32/Xil_Out32), PC: host/npu_hal_trace.c (기록) */
#ifndef NPU_HAL_H
#define NPU_HAL_H
#include <stdint.h>

void     npu_wr(uint32_t off, uint32_t value);
uint32_t npu_rd(uint32_t off);
/* off를 읽어 (값 & mask) != 0이 될 때까지 최대 limit번 읽는다. 성공하면 마지막 값, 실패하면 0 */
uint32_t npu_poll(uint32_t off, uint32_t mask, uint32_t limit);

#endif
