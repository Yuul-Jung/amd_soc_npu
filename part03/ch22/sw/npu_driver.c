/* (추가) 22장: p3_npu_axi_lite 드라이버 구현. 20장 docs/README.md의 "CPU 실행 순서"를 그대로 따른다. */
#include "npu_driver.h"

static void wr(npu_t *npu, uint32_t off, uint32_t v) { npu_io_write(npu->base + off, v); }
static uint32_t rd(npu_t *npu, uint32_t off) { return npu_io_read(npu->base + off); }

void npu_init(npu_t *npu, uintptr_t base)
{
    npu->base = base;
    npu->last_status = 0;
    npu->poll_limit = 100000u;
    wr(npu, NPU_IRQ_EN, 0);
    wr(npu, NPU_STATUS, NPU_ST_DONE | NPU_ST_ERROR);   /* W1C */
}

uint32_t npu_last_status(const npu_t *npu) { return npu->last_status; }

void npu_irq_enable(npu_t *npu, int enable) { wr(npu, NPU_IRQ_EN, enable ? 1u : 0u); }

void npu_clear_done(npu_t *npu) { wr(npu, NPU_STATUS, NPU_ST_DONE); }

/* STATUS가 (s & mask) == want가 될 때까지 폴링. 도중 ERROR면 실패. */
static int wait_status(npu_t *npu, uint32_t mask, uint32_t want)
{
    uint32_t n;
    for (n = 0; n < npu->poll_limit; n++) {
        uint32_t s = rd(npu, NPU_STATUS);
        npu->last_status = s;
        if (s & NPU_ST_ERROR)
            return NPU_E_HW;
        if ((s & mask) == want)
            return NPU_OK;
    }
    return NPU_E_TIMEOUT;
}

int npu_set_bias(npu_t *npu, const int64_t bias[NPU_N_CLASS])
{
    int c;
    for (c = 0; c < NPU_N_CLASS; c++) {
        uint64_t b = (uint64_t)bias[c];
        wr(npu, NPU_W_CLASS, (uint32_t)c);
        wr(npu, NPU_BIAS_LO, (uint32_t)b);
        /* [39:32]를 32비트로 부호 확장 */
        wr(npu, NPU_BIAS_HI, (uint32_t)(int32_t)(int8_t)(uint8_t)(b >> 32));
    }
    npu->last_status = rd(npu, NPU_STATUS);
    return (npu->last_status & NPU_ST_ERROR) ? NPU_E_HW : NPU_OK;
}

int npu_infer(npu_t *npu, const int8_t x[NPU_N_IN], const int8_t w[NPU_N_CLASS][NPU_N_IN],
              int64_t scores[NPU_N_CLASS], int *class_id)
{
    int t, c, i, rc;
    wr(npu, NPU_STATUS, NPU_ST_DONE | NPU_ST_ERROR);
    wr(npu, NPU_CTRL, NPU_CTRL_START);
    for (t = 0; t < NPU_N_TILE; t++) {
        int base = t * NPU_TILE;
        int len = (t == NPU_N_TILE - 1) ? (NPU_N_IN - base) : NPU_TILE;
        rc = wait_status(npu, NPU_ST_BUSY | NPU_ST_LOAD_READY, NPU_ST_BUSY | NPU_ST_LOAD_READY);
        if (rc != NPU_OK)
            return rc;
        for (c = 0; c < NPU_N_CLASS; c++) {
            wr(npu, NPU_W_CLASS, (uint32_t)c);
            wr(npu, NPU_W_INDEX, 0);
            for (i = 0; i < len; i++)
                wr(npu, NPU_W_DATA, (uint32_t)(int32_t)w[c][base + i]);
        }
        wr(npu, NPU_X_INDEX, 0);
        for (i = 0; i < NPU_TILE; i++)   /* 마지막 타일의 48개는 0으로 채운다(하드웨어가 무시) */
            wr(npu, NPU_X_DATA, (uint32_t)(int32_t)(i < len ? x[base + i] : 0));
        wr(npu, NPU_CTRL, NPU_CTRL_TILE_GO | ((uint32_t)t << 8));
        /* 결과 수락 = X_HELD 해제 */
        rc = wait_status(npu, NPU_ST_X_HELD, 0);
        if (rc != NPU_OK)
            return rc;
    }
    rc = wait_status(npu, NPU_ST_DONE, NPU_ST_DONE);
    if (rc != NPU_OK)
        return rc;
    for (c = 0; c < NPU_N_CLASS; c++) {
        uint32_t lo, hi;
        wr(npu, NPU_SCORE_SEL, (uint32_t)c);
        lo = rd(npu, NPU_SCORE_LO);      /* LO 먼저: HI는 이 순간의 스냅샷 */
        hi = rd(npu, NPU_SCORE_HI);
        scores[c] = (int64_t)(((uint64_t)hi << 32) | lo);
    }
    *class_id = (int)rd(npu, NPU_CLASS);
    return (npu->last_status & NPU_ST_OVF) ? NPU_E_OVERFLOW : NPU_OK;
}

int cpu_infer(const int8_t x[NPU_N_IN], const int8_t w[NPU_N_CLASS][NPU_N_IN],
              const int64_t bias[NPU_N_CLASS], int64_t scores[NPU_N_CLASS])
{
    int c, i, best = 0;
    for (c = 0; c < NPU_N_CLASS; c++) {
        int64_t acc = 0;
        for (i = 0; i < NPU_N_IN; i++)
            acc += (int32_t)x[i] * (int32_t)w[c][i];
        scores[c] = acc + bias[c];
        if (scores[c] > scores[best])   /* 동점은 낮은 번호 */
            best = c;
    }
    return best;
}
