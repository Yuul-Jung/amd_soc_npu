/* 27장 보드 입출력: AXI GPIO(제1부 11장, 0x4000_0000) 채널 1 = LED 출력, 채널 2 = 스위치 입력 */
#ifndef BOARD_IO_H
#define BOARD_IO_H
#include <stdint.h>

void     led_write(uint32_t v);
uint32_t sw_read(void);

/* LED 워드 약속 (27장 fnd_class_display.v와 같음): [9:0] 원핫, [13:10] 클래스, [14] 오류, [15] 결과 있음 */
static inline uint32_t led_word(uint32_t cls, int err)
{
    if (err) return 1u << 14;
    return (1u << 15) | ((cls & 0xFu) << 10) | (1u << cls);
}

#endif
