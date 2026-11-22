/* (추가) 28장: UART 손글씨 숫자 → 784 INT8 → 20장 NPU(13타일) → 10개 점수·Class → UART·LED·FND.
 * MicroBlaze V는 프레임 수신·검사, NPU 버스 제어, 결과 전송만 한다. 10개 점수의 MAC은 NPU RTL이 한다.
 * 같은 입력으로 CPU 정수 추론(cpu_infer)도 실행해 NPU 점수와 비교한다(불일치면 표시하지 않고 오류 7).
 * 표시 규칙: Class는 NPU DONE·rc=0·모델 ID 일치·NPU=CPU일 때만 FND/LED에 쓴다. 그 밖에는 오류 표시.
 */
#include "app.h"
#include "npu_driver.h"
#include "digit_app.h"
#include "digit_io.h"
#include "digit_model.h"

static uint8_t rx_buf[DIGIT_HDR_BYTES + DIGIT_N_IN];
static int8_t x_buf[DIGIT_N_IN];
static char line_buf[16 * NPU_N_CLASS];
static int model_ok;                    /* 부팅 때 ROM 모델 CRC32 = DIGIT_MODEL_ID, Bias 적재 성공 */

uint16_t digit_crc16(const uint8_t *p, uint32_t n, uint16_t crc)
{
    uint32_t i;
    int b;
    for (i = 0; i < n; i++) {
        crc ^= (uint16_t)p[i] << 8;
        for (b = 0; b < 8; b++)
            crc = (crc & 0x8000u) ? (uint16_t)((crc << 1) ^ 0x1021u) : (uint16_t)(crc << 1);
    }
    return crc;
}

static uint32_t crc32_byte(uint32_t crc, uint8_t v)
{
    int b;
    crc ^= v;
    for (b = 0; b < 8; b++)
        crc = (crc & 1u) ? (crc >> 1) ^ 0xEDB88320u : crc >> 1;
    return crc;
}

/* zlib.crc32(w ‖ b(int64 LE)) — ROM 모델이 Python 모델과 같은지 부팅 때 확인 */
uint32_t digit_model_crc32(void)
{
    uint32_t crc = 0xFFFFFFFFu;
    int c, i;
    for (c = 0; c < NPU_N_CLASS; c++)
        for (i = 0; i < DIGIT_N_IN; i++)
            crc = crc32_byte(crc, (uint8_t)model_w[c][i]);
    for (c = 0; c < NPU_N_CLASS; c++) {
        uint64_t v = (uint64_t)model_b[c];
        for (i = 0; i < 8; i++)
            crc = crc32_byte(crc, (uint8_t)(v >> (8 * i)));
    }
    return ~crc;
}

/* xil_printf에 64비트 서식이 없어 직접 10진 변환 */
static char *fmt_i64(char *p, int64_t v)
{
    char tmp[20];
    int n = 0;
    uint64_t u = v < 0 ? (uint64_t)(-(v + 1)) + 1u : (uint64_t)v;
    if (v < 0)
        *p++ = '-';
    do {
        tmp[n++] = (char)('0' + (int)(u % 10u));
        u /= 10u;
    } while (u);
    while (n)
        *p++ = tmp[--n];
    return p;
}

static void show(uint32_t fnd, uint32_t led)
{
    dio_display(fnd, led);
    APP_PRINTF("DISP fnd=%08x led=%04x\r\n", (unsigned)fnd, (unsigned)led);
    dio_flush();
}

static void report_error(int img, int code, const char *name, int detail, int junk)
{
    uint32_t fnd = (0xEu << 4) | (uint32_t)code;
    fnd |= img >= 0 ? (((uint32_t)img & 0xFFu) << 8) | FND_ON(0xF) : FND_ON(0x3);
    APP_PRINTF("ERROR img=%d code=%d name=%s detail=%d junk=%d\r\n", img, code, name, detail, junk);
    show(fnd, LED_ERROR);
}

/* NPU를 IDLE로 되돌린다: LOAD 중이면 ABORT, 계산 중이면 LOAD_READY/IDLE까지 대기, 끝으로 DONE·ERROR W1C */
static uint32_t npu_recover(npu_t *npu)
{
    uint32_t s = 0, n;
    for (n = 0; n < npu->poll_limit; n++) {
        s = npu_io_read(npu->base + NPU_STATUS);
        if (!(s & NPU_ST_BUSY) || (s & NPU_ST_LOAD_READY))
            break;
    }
    if ((s & NPU_ST_BUSY) && (s & NPU_ST_LOAD_READY))
        npu_io_write(npu->base + NPU_CTRL, NPU_CTRL_ABORT);
    npu_io_write(npu->base + NPU_STATUS, NPU_ST_DONE | NPU_ST_ERROR);
    return npu_io_read(npu->base + NPU_STATUS);
}

/* 가중치 미적재 시험: x 64개만 쓰고 TILE_GO → ERR_CODE 9 기대, 이후 ABORT로 복구 */
static void selftest_w_missing(npu_t *npu)
{
    uint32_t s, code = 0, n;
    int i, recovered;
    npu_io_write(npu->base + NPU_STATUS, NPU_ST_DONE | NPU_ST_ERROR);
    npu_io_write(npu->base + NPU_CTRL, NPU_CTRL_START);
    for (n = 0; n < npu->poll_limit; n++)
        if (npu_io_read(npu->base + NPU_STATUS) & NPU_ST_LOAD_READY)
            break;
    npu_io_write(npu->base + NPU_X_INDEX, 0);
    for (i = 0; i < NPU_TILE; i++)
        npu_io_write(npu->base + NPU_X_DATA, 0);
    npu_io_write(npu->base + NPU_CTRL, NPU_CTRL_TILE_GO);
    s = npu_io_read(npu->base + NPU_STATUS);
    if (s & NPU_ST_ERROR)
        code = NPU_ST_ERR_CODE(s);
    s = npu_recover(npu);
    recovered = !(s & (NPU_ST_BUSY | NPU_ST_ERROR | NPU_ST_DONE));
    APP_PRINTF("SELFTEST w_missing err_code=%d recovered=%d status=%08x\r\n", (int)code, recovered, (unsigned)s);
    if (code == 9u && recovered)
        show(FND_ON(0x3) | 0x00u, 0);                 /* "00": 자체 시험 통과 */
    else
        report_error(-1, DIGIT_ERR_NPU, "SELFTEST", (int)code, 0);
}

static void infer(npu_t *npu, int junk)
{
    int64_t ns[NPU_N_CLASS], cs[NPU_N_CLASS];
    int img = rx_buf[0] | (rx_buf[1] << 8);
    uint32_t mid = rx_buf[2] | ((uint32_t)rx_buf[3] << 8) | ((uint32_t)rx_buf[4] << 16) | ((uint32_t)rx_buf[5] << 24);
    int i, c, rc, ncls = -1, ccls, same = 1;
    char *p = line_buf;
    if (mid != DIGIT_MODEL_ID || !model_ok) {
        report_error(img, DIGIT_ERR_MODEL, "MODEL", model_ok, junk);
        return;
    }
    for (i = 0; i < DIGIT_N_IN; i++) {
        uint8_t v = rx_buf[DIGIT_HDR_BYTES + i];     /* int8 2의 보수: 0x80 이상은 음수 */
        x_buf[i] = (int8_t)v;
        if (v > DIGIT_PIX_MAX) {                        /* 전처리 계약: 0..127 */
            report_error(img, DIGIT_ERR_RANGE, "RANGE", i, junk);
            return;
        }
    }
    rc = npu_infer(npu, x_buf, model_w, ns, &ncls);
    if (rc != NPU_OK) {
        uint32_t st = npu_last_status(npu);
        npu_recover(npu);
        report_error(img, DIGIT_ERR_NPU, rc == NPU_E_TIMEOUT ? "NPU_TIMEOUT" : rc == NPU_E_OVERFLOW ? "NPU_OVF" : "NPU_HW",
                     (int)NPU_ST_ERR_CODE(st), junk);
        return;
    }
    ccls = cpu_infer(x_buf, model_w, model_b, cs);
    for (c = 0; c < NPU_N_CLASS; c++) {
        if (ns[c] != cs[c])
            same = 0;
        if (c)
            *p++ = ',';
        p = fmt_i64(p, ns[c]);
    }
    *p = '\0';
    npu_clear_done(npu);
    if (ncls != ccls)
        same = 0;
    APP_PRINTF("RESULT img=%d model=%08x npu_class=%d cpu_class=%d match=%d rc=%d status=%08x junk=%d scores=%s\r\n",
               img, (unsigned)mid, ncls, ccls, same, rc, (unsigned)npu_last_status(npu), junk, line_buf);
    if (!same || ncls < 0 || ncls > 9) {
        report_error(img, DIGIT_ERR_MISMATCH, "MISMATCH", ncls, junk);
        return;
    }
    show((((uint32_t)img & 0xFFu) << 8) | (uint32_t)ncls | FND_ON(0xD), (1u << ncls) | LED_VALID);
}

/* 프레임 1개 수신·처리. 반환 0: 계속, -1: 입력 종료(PC) */
static int handle_frame(npu_t *npu)
{
    int c, prev = -1, junk = 0, cmd;
    uint32_t i, len;
    uint16_t crc;
    uint8_t b;
    for (;;) {                                         /* 동기 'P' '3' 찾기, 그 앞 바이트는 버린다 */
        c = dio_getc(1);
        if (c == DIO_EOF)
            return -1;
        if (prev == 'P' && c == '3')
            break;
        if (prev >= 0)
            junk++;
        prev = c;
    }
    cmd = dio_getc(0);
    if (cmd < 0) {
        report_error(-1, DIGIT_ERR_TIMEOUT, "TIMEOUT", 0, junk);
        return cmd == DIO_EOF ? -1 : 0;
    }
    if (cmd == 'X')
        len = DIGIT_HDR_BYTES + DIGIT_N_IN;
    else if (cmd == 'I' || cmd == 'T')
        len = 0;
    else {                                             /* 길이를 모르므로 바이트가 끊길 때까지 버린다 */
        while ((c = dio_getc(0)) >= 0)
            ;
        report_error(-1, DIGIT_ERR_CMD, "CMD", cmd, junk);
        return c == DIO_EOF ? -1 : 0;
    }
    b = (uint8_t)cmd;
    crc = digit_crc16(&b, 1, 0xFFFFu);
    for (i = 0; i < len + 2; i++) {                    /* payload + CRC 2바이트(상위 먼저) */
        c = dio_getc(0);
        if (c < 0) {
            report_error(-1, DIGIT_ERR_TIMEOUT, "TIMEOUT", (int)i, junk);
            return c == DIO_EOF ? -1 : 0;
        }
        if (i < len)
            rx_buf[i] = (uint8_t)c;
        b = (uint8_t)c;
        crc = digit_crc16(&b, 1, crc);
    }
    if (crc != 0) {                                    /* CRC 포함 잔여값 0 */
        report_error(-1, DIGIT_ERR_CRC, "CRC", (int)len, junk);
        return 0;
    }
    if (cmd == 'I') {
        APP_PRINTF("P3_DIGIT READY model=%08x model_ok=%d mode=784x8 tiles=13 junk=%d\r\n",
                   (unsigned)DIGIT_MODEL_ID, digit_model_crc32() == DIGIT_MODEL_ID, junk);
        dio_flush();
    } else if (cmd == 'T') {
        selftest_w_missing(npu);
    } else {
        infer(npu, junk);
    }
    return 0;
}

int digit_app_run(uintptr_t npu_base)
{
    npu_t npu;
    int frames = 0, rc;
    uint32_t mcrc = digit_model_crc32();
    npu_init(&npu, npu_base);
    rc = npu_set_bias(&npu, model_b);
    APP_PRINTF("P3_DIGIT READY model=%08x model_ok=%d mode=784x8 tiles=13 bias_rc=%d\r\n",
               (unsigned)DIGIT_MODEL_ID, mcrc == DIGIT_MODEL_ID, rc);
    model_ok = mcrc == DIGIT_MODEL_ID && rc == NPU_OK;
    if (!model_ok)
        report_error(-1, DIGIT_ERR_MODEL, "BOOT", rc, 0);   /* 모델 ROM 손상 또는 Bias 적재 실패: 계속 오류 표시 */
    else
        show(((DIGIT_MODEL_ID >> 16) & 0xFFFFu) | FND_ON(0xF), 0);
    while (handle_frame(&npu) == 0)
        frames++;
    return frames;
}
