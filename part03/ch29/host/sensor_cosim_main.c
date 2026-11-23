/* PC 시뮬레이션 main. sensor_app_run()은 보드와 같은 코드이고, NPU 레지스터 접근은
 * 5-3 npu_io_cosim.c가 FIFO로 RTL(5-1 AXI NPU)에 전달한다. UART는 표준 입출력.
 */
#include <stdio.h>
#include "sensor_app.h"

void cosim_open(const char *cmd_path, const char *rsp_path);
void cosim_close(void);

int main(int argc, char **argv)
{
    int frames;
    if (argc != 3) {
        fprintf(stderr, "usage: %s <cmd fifo> <rsp fifo>\n", argv[0]);
        return 2;
    }
    cosim_open(argv[1], argv[2]);
    frames = sensor_app_run(0);
    cosim_close();
    fprintf(stderr, "C_SENSOR_APP_EXIT frames=%d\n", frames);
    return 0;
}
