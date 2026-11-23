/* 보드 표시. 클래스 = LED 한 개(AXI GPIO 0) + 7세그먼트 오른쪽 자리, 왼쪽 두 자리 = 그림 번호.
 * 주소는 xparameters.h만 쓴다(XPAR_AXI_GPIO_0_BASEADDR, XPAR_IP06_SEG7_BASEADDR). */
#include "xparameters.h"
#include "xil_io.h"
#include "p3_seg7.h"
#include "app.h"

void app_show(int picture, int cls)
{
    p3_seg7_regs_t r = { APP_SHOW_VALUE(picture, cls), APP_SHOW_MODE, 0u };
    p3_seg7_write(r);
    Xil_Out32(XPAR_AXI_GPIO_0_BASEADDR, APP_SHOW_LED(cls));
}
