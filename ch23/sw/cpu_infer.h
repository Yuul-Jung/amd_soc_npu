/* 23장 CPU 기준 추론: NPU와 같은 정수 계산(784×10 내적 + Bias, 동점은 낮은 번호)을 C로 한다. */
#ifndef CPU_INFER_H
#define CPU_INFER_H
#include <stdint.h>

uint32_t cpu_infer(const int8_t w[10][784], const int32_t b[10], const uint8_t x[784], int32_t score[10]);

#endif
