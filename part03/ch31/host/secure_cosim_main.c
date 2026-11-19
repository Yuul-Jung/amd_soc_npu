/* (추가) 31장: PC 협동 시뮬레이션 main(22장 FIFO 브리지 → 20장 NPU RTL, UART = 표준 입출력). */
#include <stdio.h>
#include "secure_app.h"

void cosim_open(const char *cmd_path, const char *rsp_path);
void cosim_close(void);

int main(int argc, char **argv)
{
    int n;
    if (argc != 3) {
        fprintf(stderr, "usage: %s <cmd fifo> <rsp fifo>\n", argv[0]);
        return 2;
    }
    cosim_open(argv[1], argv[2]);
    n = secure_app_run(0);
    cosim_close();
    fprintf(stderr, "C_SECURE_APP_EXIT responses=%d\n", n);
    return 0;
}
