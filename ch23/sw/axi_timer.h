/* 23장 AXI Timer 0번 카운터를 자유 증가 카운터로 쓴다 (레지스터 직접 접근, PG079 레지스터 표). */
#ifndef AXI_TIMER_H
#define AXI_TIMER_H
#include <stdint.h>
#include "xil_io.h"

#ifndef TIMER_BASE
/* ⚠ xparameters.h의 AXI Timer 기준 주소로 바꾼다 (제1부 11장 SoC의 값). 0x41C00000은 Vivado 기본값이며 미확인. */
#define TIMER_BASE 0x41C00000u
#endif
#define TMR_TCSR0 0x00u     /* 제어·상태 */
#define TMR_TLR0  0x04u     /* 적재 값 */
#define TMR_TCR0  0x08u     /* 카운터 */
#define TCSR_LOAD 0x20u     /* TLR 값을 카운터에 적재 */
#define TCSR_ENT  0x80u     /* 카운터 동작 (UDT0=0: 위로 셈) */

static inline void timer_start(void)
{
    Xil_Out32(TIMER_BASE + TMR_TLR0, 0);
    Xil_Out32(TIMER_BASE + TMR_TCSR0, TCSR_LOAD);   /* 0 적재 */
    Xil_Out32(TIMER_BASE + TMR_TCSR0, TCSR_ENT);    /* 위로 세기 시작 */
}
static inline uint32_t timer_now(void) { return Xil_In32(TIMER_BASE + TMR_TCR0); }

#endif
