/* (추가) 22장: MicroBlaze V 대상 레지스터 접근(Vitis standalone BSP의 Xil_In32/Xil_Out32). */
#include "xil_io.h"
#include "npu_driver.h"

uint32_t npu_io_read(uintptr_t addr) { return Xil_In32(addr); }

void npu_io_write(uintptr_t addr, uint32_t value) { Xil_Out32(addr, value); }
