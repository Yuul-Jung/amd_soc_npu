/* 22장 PC 시험용 가짜 NPU: 오류 경로(ID 틀림, BUSY, 시간 초과, ERROR)를 드라이버가 구별하는지 본다. */
#include "npu_hal.h"
#include "npu_regs.h"

uint32_t fake_id = NPU_ID_VALUE, fake_status = 0, fake_reads = 0;

void npu_wr(uint32_t off, uint32_t value) { (void)off; (void)value; }

uint32_t npu_rd(uint32_t off)
{
    fake_reads++;
    return off == NPU_ID ? fake_id : off == NPU_STATUS ? fake_status : 0u;
}

uint32_t npu_poll(uint32_t off, uint32_t mask, uint32_t limit)
{
    while (limit-- != 0u) {
        uint32_t v = npu_rd(off);
        if (v & mask) return v;
    }
    return 0u;
}
