/* 28장 틀 해석: 바이트 하나씩 넣는다. 'N' 전의 바이트는 버리고(잡음·줄바꿈), 틀이 끝나면 검사합·범위를 판정한다. */
#include "proto.h"

void proto_reset(proto_t *p) { p->pos = 0; p->sum = 0; p->bad = 0; }

proto_ev_t proto_feed(proto_t *p, uint8_t c)
{
    if (p->pos == 0) {
        if (c == 'N') { p->pos = 1; p->sum = 0; p->bad = 0; }
        return PROTO_BUSY;
    }
    if (p->pos <= PROTO_N) {
        p->x[p->pos - 1] = c;
        p->sum = (uint8_t)(p->sum + c);
        if (c > 127) p->bad = 1;
        p->pos++;
        return PROTO_BUSY;
    }
    p->pos = 0;                                     /* 검사합 바이트 */
    if (c != p->sum) return PROTO_ERR_SUM;
    if (p->bad) return PROTO_ERR_RANGE;
    return PROTO_FRAME;
}
