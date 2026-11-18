/* 22장 PC 시험: 가짜 NPU로 드라이버의 오류 코드 5가지를 확인한다. */
#include <stdio.h>
#include "npu_drv.h"

extern uint32_t fake_id, fake_status, fake_reads;
static int fails;
#define CHECK(c, m) do { if (!(c)) { printf("  FAIL %s\n", m); fails++; } else printf("  ok   %s\n", m); } while (0)

int main(void)
{
    static const uint8_t x[NPU_N_IN];
    npu_result_t r;
    fake_id = 0x12345678u;            CHECK(npu_init() == NPU_ERR_ID, "ID가 다르면 NPU_ERR_ID");
    fake_id = NPU_ID_VALUE;           CHECK(npu_init() == NPU_OK, "ID가 맞으면 NPU_OK");
    fake_status = NPU_ST_BUSY;        CHECK(npu_load_input(x) == NPU_ERR_BUSY, "BUSY 중 입력 적재 거부");
                                      CHECK(npu_run(&r, 10) == NPU_ERR_BUSY, "BUSY 중 시작 거부");
    fake_status = 0; fake_reads = 0;  CHECK(npu_run(&r, 50) == NPU_ERR_TIMEOUT && fake_reads == 51, "DONE이 없으면 상한 50번 읽고 NPU_ERR_TIMEOUT");
    fake_status = NPU_ST_ERROR;       CHECK(npu_run(&r, 50) == NPU_ERR_HW, "ERROR만 와도 NPU_ERR_HW (DONE을 기다리지 않음)");
    fake_status = NPU_ST_DONE | NPU_ST_ERROR; CHECK(npu_run(&r, 50) == NPU_ERR_HW, "DONE·ERROR가 같이 오면 NPU_ERR_HW");
    if (fails) { printf("HOST_DRIVER_TEST_FAIL fails=%d\n", fails); return 1; }
    printf("HOST_DRIVER_TEST_PASS cases=7\n");
    return 0;
}
