/* 22장 MicroBlaze V용 레지스터 접근. NPU 기준 주소는 21장 Address Editor 값이며, BSP xparameters.h의 매크로로 바꾼다. */
#include "npu_hal.h"
#include "xil_io.h"
#include "xparameters.h"

#ifndef NPU_BASE
/* ⚠ 모듈 참조 셀의 매크로 이름은 BSP마다 다르다. xparameters.h에서 0x44A00000을 찾아 그 이름으로 바꾼다. */
#define NPU_BASE 0x44A00000u
#endif

void npu_wr(uint32_t off, uint32_t value) { Xil_Out32(NPU_BASE + off, value); }

uint32_t npu_rd(uint32_t off) { return Xil_In32(NPU_BASE + off); }

uint32_t npu_poll(uint32_t off, uint32_t mask, uint32_t limit)
{
    while (limit-- != 0u) {
        uint32_t v = Xil_In32(NPU_BASE + off);
        if ((v & mask) != 0u) return v;
    }
    return 0u;
}
