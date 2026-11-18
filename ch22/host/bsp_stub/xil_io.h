/* 22장 교차 컴파일 확인용 대역 (Vitis BSP의 xil_io.h가 아님). 보드 빌드에서는 BSP 헤더를 쓴다. */
#ifndef XIL_IO_H
#define XIL_IO_H
#include <stdint.h>
static inline void Xil_Out32(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a = v; }
static inline uint32_t Xil_In32(uintptr_t a) { return *(volatile uint32_t *)a; }
#endif
