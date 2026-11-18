/* (추가) 22장: PC 협동 시뮬레이션 main. 같은 app_run()을 실행하고 레지스터 접근은 FIFO로 RTL에 보낸다. */
#include <stdio.h>
#include "app.h"
#include "npu_driver.h"

void cosim_open(const char *cmd_path, const char *rsp_path);
void cosim_close(void);

/* CPU 기준 argmax 동점 규칙(낮은 번호) 자체 시험: x=0이면 점수 = Bias */
static int cpu_tie_selftest(void)
{
    static int8_t x[NPU_N_IN], w[NPU_N_CLASS][NPU_N_IN];
    int64_t b[NPU_N_CLASS], s[NPU_N_CLASS];
    int c, pair, bad = 0;
    for (pair = 0; pair < NPU_N_CLASS - 1; pair++) {
        for (c = 0; c < NPU_N_CLASS; c++)
            b[c] = -100 - c;
        b[pair] = b[pair + 1] = 5;
        if (cpu_infer(x, w, b, s) != pair)
            bad++;
    }
    printf("CPU_TIE_SELFTEST pairs=%d bad=%d\n", NPU_N_CLASS - 1, bad);
    return bad;
}

int main(int argc, char **argv)
{
    int failures;
    if (argc != 3) {
        fprintf(stderr, "usage: %s <cmd fifo> <rsp fifo>\n", argv[0]);
        return 2;
    }
    failures = cpu_tie_selftest();
    cosim_open(argv[1], argv[2]);
    failures += app_run(0);
    cosim_close();
    return failures ? 1 : 0;
}
