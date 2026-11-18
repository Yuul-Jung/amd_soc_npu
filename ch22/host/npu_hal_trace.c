/* 22장 PC용 레지스터 접근: 실제 버스 대신 접근 순서를 파일에 기록한다 (RTL 재생용).
 * 형식: W 주소 값 / R 주소 / P 주소 마스크 상한. 읽기 값은 재생할 때 RTL이 정하므로 여기서는
 * 드라이버가 다음으로 넘어갈 수 있는 값만 돌려준다 (ID = 0x4E505531, STATUS = 0, 폴링 = 성공). */
#include <stdio.h>
#include <stdlib.h>
#include "npu_hal.h"
#include "npu_regs.h"

static FILE *trace_fp(void)
{
    static FILE *fp;
    if (!fp) {
        const char *p = getenv("NPU_TRACE");
        fp = p ? fopen(p, "w") : stdout;
        if (!fp) { perror("NPU_TRACE"); exit(2); }
    }
    return fp;
}

void npu_wr(uint32_t off, uint32_t value) { fprintf(trace_fp(), "W %u %u\n", off, value); }

uint32_t npu_rd(uint32_t off)
{
    fprintf(trace_fp(), "R %u\n", off);
    return off == NPU_ID ? NPU_ID_VALUE : 0u;
}

uint32_t npu_poll(uint32_t off, uint32_t mask, uint32_t limit)
{
    fprintf(trace_fp(), "P %u %u %u\n", off, mask, limit);
    return mask & NPU_ST_DONE;
}
