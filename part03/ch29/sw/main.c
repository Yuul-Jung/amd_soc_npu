/* MicroBlaze V main. NPU 베이스 주소는 Vivado Address Editor 값(xparameters.h, 6-1 XSA). */
#include "xparameters.h"
#include "sensor_app.h"

int main(void)
{
    sensor_app_run(XPAR_P3_NPU_0_BASEADDR);   /* 보드에서는 돌아오지 않는다 */
    return 0;
}
