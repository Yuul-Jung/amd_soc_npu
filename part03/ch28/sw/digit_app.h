/* UART 숫자 인식 응용(784 입력·INT8·13타일 NPU). 규약은 reference/digit_reference.py 머리말과 같다. */
#ifndef DIGIT_APP_H
#define DIGIT_APP_H
#include <stdint.h>

#define DIGIT_N_IN      784
#define DIGIT_PIX_MAX   127
#define DIGIT_HDR_BYTES 6            /* img_id u16 + model_id u32 */

enum {
    DIGIT_ERR_CRC = 1, DIGIT_ERR_TIMEOUT = 2, DIGIT_ERR_CMD = 3, DIGIT_ERR_MODEL = 4,
    DIGIT_ERR_RANGE = 5, DIGIT_ERR_NPU = 6, DIGIT_ERR_MISMATCH = 7
};

/* FND 표시 워드: [15:0] 자리별 nibble(자리 0 = 오른쪽), [19:16] 자리 켜짐, [23:20] 점 */
#define FND_ON(m)  ((uint32_t)(m) << 16)
#define LED_VALID  (1u << 15)
#define LED_ERROR  (1u << 14)

uint16_t digit_crc16(const uint8_t *p, uint32_t n, uint16_t crc);
uint32_t digit_model_crc32(void);
/* 프레임을 받아 처리하는 루프. PC 빌드는 입력이 끝나면 처리한 프레임 수를 돌려준다(보드는 돌아오지 않음). */
int digit_app_run(uintptr_t npu_base);

#endif
