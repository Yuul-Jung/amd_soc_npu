/* 27장 MicroBlaze V용 GPIO 직접 접근 (PG144: GPIO_DATA 0x00, GPIO2_DATA 0x08) */
#include "board_io.h"
#include "xil_io.h"

#ifndef GPIO_BASE
#define GPIO_BASE 0x40000000u   /* 제1부 11장 xparameters.h XPAR_XGPIO_0_BASEADDR 확인값 */
#endif

void led_write(uint32_t v) { Xil_Out32(GPIO_BASE + 0x00u, v & 0xFFFFu); }
uint32_t sw_read(void) { return Xil_In32(GPIO_BASE + 0x08u) & 0xFFFFu; }
