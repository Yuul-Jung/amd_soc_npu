/* (추가) 28장: PC 협동 시뮬레이션 main. digit_app_run()은 보드와 같은 코드이고, NPU 레지스터 접근은
 * 22장 npu_io_cosim.c가 FIFO로 Icarus RTL(20장 AXI NPU)에 전달한다. UART는 표준 입출력.
 * 시작 전에 CRC16 검사값(0x29B1)을 확인해 C 구현이 Python 규약과 같은지 본다.
 */
#include <stdio.h>
#include "digit_app.h"

void cosim_open(const char *cmd_path, const char *rsp_path);
void cosim_close(void);

int main(int argc, char **argv)
{
    int frames;
    uint16_t crc = digit_crc16((const uint8_t *)"123456789", 9, 0xFFFFu);
    if (argc != 3) {
        fprintf(stderr, "usage: %s <cmd fifo> <rsp fifo>\n", argv[0]);
        return 2;
    }
    fprintf(stderr, "C_CRC16_CHECK value=%04x expect=29b1\n", crc);
    if (crc != 0x29B1u)
        return 1;
    cosim_open(argv[1], argv[2]);
    frames = digit_app_run(0);
    cosim_close();
    fprintf(stderr, "C_DIGIT_APP_EXIT frames=%d\n", frames);
    return 0;
}
