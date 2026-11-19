/* (추가) 22장: MicroBlaze V 응용 main. NPU 베이스 주소는 Vivado Address Editor 값(xparameters.h)을 쓴다. */
#include "xparameters.h"
#include "app.h"

#ifndef NPU_BASEADDR
#define NPU_BASEADDR XPAR_P3_NPU_0_BASEADDR
#endif

int main(void)
{
    APP_PRINTF("P3 NPU driver test base=0x%08x\r\n", (unsigned)NPU_BASEADDR);
    return app_run(NPU_BASEADDR);
}
