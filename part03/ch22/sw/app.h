/* (추가) 22장: 응용 진입점과 출력 매크로. 대상에서는 xil_printf(64비트 서식 없음), PC에서는 printf. */
#ifndef APP_H
#define APP_H
#include <stdint.h>
#ifdef NPU_HOST_SIM
#include <stdio.h>
#define APP_PRINTF printf
#else
#include "xil_printf.h"
#define APP_PRINTF xil_printf
#endif
int app_run(uintptr_t npu_base);
#endif
