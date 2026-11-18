/* 28장 UART 그림 틀: 'N' + 784바이트(INT8 0~127) + 검사합(784바이트 합의 하위 8비트) = 786바이트 */
#ifndef PROTO_H
#define PROTO_H
#include <stdint.h>

#define PROTO_N 784
typedef enum { PROTO_BUSY = 0, PROTO_FRAME = 1, PROTO_ERR_SUM = -1, PROTO_ERR_RANGE = -2 } proto_ev_t;

typedef struct {
    uint32_t pos;          /* 0: 'N' 기다림, 1~784: 받은 화소 수 + 1 */
    uint8_t  sum, bad;
    uint8_t  x[PROTO_N];
} proto_t;

void       proto_reset(proto_t *p);
proto_ev_t proto_feed(proto_t *p, uint8_t c);

#endif
