/* 22장 NPU 드라이버 — 레지스터 순서는 20장 TB와 같다. */
#include "npu_drv.h"
#include "npu_hal.h"

npu_status_t npu_init(void)
{
    if (npu_rd(NPU_ID) != NPU_ID_VALUE) return NPU_ERR_ID;
    npu_wr(NPU_CTRL, NPU_CTRL_CLR);                 /* 이전 DONE·ERROR 지움 */
    return NPU_OK;
}

void npu_load_model(const int8_t w[NPU_N_OUT][NPU_N_IN], const int32_t b[NPU_N_OUT])
{
    for (uint32_t c = 0; c < NPU_N_OUT; c++) {
        npu_wr(NPU_W_ADDR, c << 16);                /* 클래스 c, 원소 0 */
        for (uint32_t i = 0; i < NPU_N_IN; i++)
            npu_wr(NPU_W_DATA, (uint32_t)(uint8_t)w[c][i]);   /* 원소 주소는 하드웨어가 +1 */
    }
    npu_wr(NPU_B_SEL, 0);
    for (uint32_t c = 0; c < NPU_N_OUT; c++)
        npu_wr(NPU_B_DATA, (uint32_t)b[c]);
}

npu_status_t npu_load_input(const uint8_t x[NPU_N_IN])
{
    if (npu_rd(NPU_STATUS) & NPU_ST_BUSY) return NPU_ERR_BUSY;   /* 실행 중 쓰기는 하드웨어가 무시한다 */
    npu_wr(NPU_X_ADDR, 0);
    for (uint32_t i = 0; i < NPU_N_IN; i++)
        npu_wr(NPU_X_DATA, x[i]);
    return NPU_OK;
}

npu_status_t npu_run(npu_result_t *out, uint32_t poll_limit)
{
    if (npu_rd(NPU_STATUS) & NPU_ST_BUSY) return NPU_ERR_BUSY;
    npu_wr(NPU_CTRL, NPU_CTRL_START);
    uint32_t st = npu_poll(NPU_STATUS, NPU_ST_DONE | NPU_ST_ERROR, poll_limit);
    if (st == 0u) return NPU_ERR_TIMEOUT;
    if (st & NPU_ST_ERROR) return NPU_ERR_HW;
    for (uint32_t k = 0; k < NPU_N_OUT; k++)
        out->score[k] = (int32_t)npu_rd(NPU_SCORE(k));
    out->cls = npu_rd(NPU_CLASS) & 0xFu;
    out->cycles = npu_rd(NPU_CYCLES) & 0xFFFFu;
    npu_wr(NPU_CTRL, NPU_CTRL_CLR);
    return NPU_OK;
}
