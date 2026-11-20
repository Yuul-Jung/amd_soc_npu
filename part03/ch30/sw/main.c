/* (추가) 30장: MicroBlaze V main. NPU·모터 GPIO 주소는 Vivado Address Editor 값(xparameters.h, 30장 XSA). (변경) 안 A: 모터 GPIO = axi_gpio_motor 0x4007_0000. */
#include "xparameters.h"
#include "motor_app.h"

int main(void)
{
    motor_app_run(XPAR_P3_NPU_0_BASEADDR, XPAR_AXI_GPIO_MOTOR_BASEADDR, 0);   /* 돌아오지 않는다 */
    return 0;
}
