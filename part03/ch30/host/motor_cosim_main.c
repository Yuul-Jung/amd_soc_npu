/* (추가) 30장: PC 협동 시뮬레이션 main. NPU(0x00)·모터 GPIO(0x100)·시험 주입(0x200) 접근은 22장 npu_io_cosim.c가
 * FIFO로 Icarus 브리지(tb_p3_motor_bridge)에 전달한다. UART는 표준 입출력(29장 sensor_io_host.c).
 */
#include <stdio.h>
#include "motor_app.h"

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
    n = motor_app_run(0x0, 0x100, 0x200);
    cosim_close();
    fprintf(stderr, "C_MOTOR_APP_EXIT responses=%d\n", n);
    return 0;
}
