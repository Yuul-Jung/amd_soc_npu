/* 28장 PC 시험용 GPIO: LED 쓰기는 버린다 (표시 확인은 27장) */
#include "board_io.h"
void led_write(uint32_t v) { (void)v; }
uint32_t sw_read(void) { return 0; }
