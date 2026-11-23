/* 응용 진입점과 출력 매크로. 대상에서는 xil_printf(64비트 서식 없음), PC에서는 printf. */
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
/* 추론 뒤 표시. 클래스 = LED 한 개 + 7세그먼트 오른쪽 자리, 왼쪽 두 자리 = 그림 번호(16진수 2자리).
 * 보드: app_show_xil.c(SEG7·GPIO 0), PC 시뮬레이션: host/cosim_main.c(SHOW 줄 출력). */
#define APP_SHOW_VALUE(pic, cls) ((((uint32_t)(pic) & 0xFFu) << 8) | ((uint32_t)(cls) & 0xFu))
#define APP_SHOW_MODE            0x200u   /* BLANK: 자리 1(가운데 오른쪽) 끔 */
#define APP_SHOW_LED(cls)        ((cls) >= 0 && (cls) < 16 ? (1u << (cls)) : 0u)
void app_show(int picture, int cls);
#endif
