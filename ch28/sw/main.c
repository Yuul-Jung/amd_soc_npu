/* 28장 손글씨 분류기: PC가 보낸 784화소 틀을 받아 NPU로 분류하고, UART로 한 줄 응답 + LED·7세그먼트 표시.
 * 응답: "CLASS c S s0 s1 … s9" / "ERR SUM" / "ERR RANGE" / "ERR NPU n" */
#include "npu_drv.h"
#include "board_io.h"
#include "proto.h"
#include "uart_io.h"
#include "model_int8.h"

static char *put_int(char *p, int32_t v)
{
    char t[12]; int n = 0; uint32_t u = v < 0 ? (uint32_t)(-(int64_t)v) : (uint32_t)v;
    if (v < 0) *p++ = '-';
    do { t[n++] = (char)('0' + u % 10u); u /= 10u; } while (u);
    while (n) *p++ = t[--n];
    return p;
}

static void answer(const uint8_t x[PROTO_N])
{
    npu_result_t r; char line[160], *p = line;
    npu_status_t s = npu_load_input(x);
    if (s == NPU_OK) s = npu_run(&r, 100000u);
    if (s != NPU_OK) {
        led_write(led_word(0, 1));
        p = put_int(line + 8, (int32_t)s); *p = 0;
        for (int i = 0; i < 8; i++) line[i] = "ERR NPU "[i];
        uart_puts(line); uart_puts("\r\n"); return;
    }
    led_write(led_word(r.cls, 0));
    *p++ = 'C'; *p++ = 'L'; *p++ = 'A'; *p++ = 'S'; *p++ = 'S'; *p++ = ' ';
    p = put_int(p, (int32_t)r.cls); *p++ = ' '; *p++ = 'S';
    for (int k = 0; k < NPU_N_OUT; k++) { *p++ = ' '; p = put_int(p, r.score[k]); }
    *p++ = '\r'; *p++ = '\n'; *p = 0;
    uart_puts(line);
}

int main(void)
{
    static proto_t pr;
    uart_puts("=== ch28 digit classifier: send 'N' + 784 bytes + sum ===\r\n");
    if (npu_init() != NPU_OK) { led_write(led_word(0, 1)); uart_puts("ERR NPU ID\r\n"); return 1; }
    npu_load_model(MODEL_W, MODEL_B);
    led_write(0);
    proto_reset(&pr);
    for (;;) {
        int c = uart_getc();
        if (c == -2) return 0;                      /* PC 시험: 입력 끝 */
        if (c < 0) continue;
        proto_ev_t ev = proto_feed(&pr, (uint8_t)c);
        if (ev == PROTO_FRAME) answer(pr.x);
        else if (ev == PROTO_ERR_SUM) { led_write(led_word(0, 1)); uart_puts("ERR SUM\r\n"); }
        else if (ev == PROTO_ERR_RANGE) { led_write(led_word(0, 1)); uart_puts("ERR RANGE\r\n"); }
    }
}
