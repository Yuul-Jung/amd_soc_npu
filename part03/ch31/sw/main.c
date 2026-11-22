/* (추가) 31장: MicroBlaze V main. 28장 SoC(Bitstream·XSA) 그대로, NPU 주소는 xparameters.h. */
#include "xparameters.h"
#include "secure_app.h"

int main(void)
{
    secure_app_run(XPAR_P3_NPU_0_BASEADDR);   /* 돌아오지 않는다 */
    return 0;
}
