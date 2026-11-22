/* (추가) 22장: PC 협동 시뮬레이션용 레지스터 접근. 명령을 FIFO로 Icarus 브리지 TB에 보내고 응답을 기다린다. */
#include <stdio.h>
#include <stdlib.h>
#include "npu_driver.h"

static FILE *cmd_fp, *rsp_fp;

void cosim_open(const char *cmd_path, const char *rsp_path)
{
    cmd_fp = fopen(cmd_path, "w");   /* TB가 읽기용으로 먼저 연다 */
    rsp_fp = fopen(rsp_path, "r");
    if (!cmd_fp || !rsp_fp) {
        fprintf(stderr, "cosim: cannot open FIFOs\n");
        exit(2);
    }
}

void cosim_close(void)
{
    fprintf(cmd_fp, "Q\n");
    fflush(cmd_fp);
    fclose(cmd_fp);
    fclose(rsp_fp);
}

void npu_io_write(uintptr_t addr, uint32_t value)
{
    int resp;
    fprintf(cmd_fp, "W %lx %08x\n", (unsigned long)addr, (unsigned)value);
    fflush(cmd_fp);
    if (fscanf(rsp_fp, " B %d", &resp) != 1 || resp != 0) {
        fprintf(stderr, "cosim: bad write response at 0x%lx\n", (unsigned long)addr);
        exit(3);
    }
}

uint32_t npu_io_read(uintptr_t addr)
{
    unsigned v;
    int resp;
    fprintf(cmd_fp, "R %lx\n", (unsigned long)addr);
    fflush(cmd_fp);
    if (fscanf(rsp_fp, " D %x %d", &v, &resp) != 2 || resp != 0) {
        fprintf(stderr, "cosim: bad read response at 0x%lx\n", (unsigned long)addr);
        exit(3);
    }
    return (uint32_t)v;
}
