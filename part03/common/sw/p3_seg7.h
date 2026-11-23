/* 표준 7세그먼트 IP ip_seg7(ID "SEG7", 0x4006_0000 = XPAR_IP06_SEG7_BASEADDR) 레지스터와
 * 6-1 표시 워드(p3_fnd_scan 형식) → SEG7 레지스터 변환. 응용과 호스트 판정은 표시 워드를 그대로 쓰고,
 * 보드 I/O 층(*_io_xil.c)만 이 변환으로 SEG7에 쓴다. 주소는 xparameters.h만 쓴다(하드코딩 금지).
 *   표시 워드: [15:0] 자리별 16진수(자리 0 = 오른쪽 an[0]), [19:16] 자리 켜짐, [23:20] 소수점
 *   SEG7     : VALUE [15:0] 16진수, MODE [3:0] RAW_EN·[11:8] BLANK(1 = 끔), DP [3:0]
 */
#ifndef P3_SEG7_H
#define P3_SEG7_H
#include <stdint.h>

#define P3_SEG7_VALUE 0x0000u
#define P3_SEG7_MODE  0x0004u
#define P3_SEG7_RAW   0x0008u
#define P3_SEG7_DP    0x000Cu
#define P3_SEG7_ID    0xFFF0u
#define P3_SEG7_ID_VALUE 0x53454737u   /* "SEG7" */

/* 인터럽트 번호(axi_intc_0 입력). NPU = In12. 지금 펌웨어는 폴링만 하고 INTC를 켜지 않는다. */
#define P3_INTC_BIT_TIMER 0
#define P3_INTC_BIT_UART  1
#define P3_INTC_BIT_BTN   3
#define P3_INTC_BIT_NPU   12

typedef struct { uint32_t value, mode, dp; } p3_seg7_regs_t;

static inline p3_seg7_regs_t p3_seg7_from_fnd_word(uint32_t w)
{
    p3_seg7_regs_t r;
    r.value = w & 0xFFFFu;
    r.mode = ((~(w >> 16)) & 0xFu) << 8;   /* 꺼진 자리 → BLANK, RAW_EN = 0 */
    r.dp = (w >> 20) & 0xFu;
    return r;
}

#ifndef NPU_HOST_SIM
#include "xparameters.h"
#include "xil_io.h"
#if defined(XPAR_AXI_INTC_0_NUM_INTR_INPUTS) && (XPAR_AXI_INTC_0_NUM_INTR_INPUTS != 16)
#error "안 A: axi_intc_0 입력은 16개여야 한다 (NPU = In12)"
#endif
#define P3_SEG7_BASE XPAR_IP06_SEG7_BASEADDR
static inline void p3_seg7_write(p3_seg7_regs_t r)
{
    Xil_Out32(P3_SEG7_BASE + P3_SEG7_MODE, r.mode);
    Xil_Out32(P3_SEG7_BASE + P3_SEG7_DP, r.dp);
    Xil_Out32(P3_SEG7_BASE + P3_SEG7_VALUE, r.value);
}
#endif
#endif
