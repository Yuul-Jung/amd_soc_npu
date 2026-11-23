/* 센서 융합 상태 감시(교육용). UART 센서 창 → 규칙 검사(guard) → 특징 6개 → 5-1 NPU(0번 타일)
 * → 3상태 후보 → 경보 정책(부팅 UNKNOWN, 상향 즉시·하향 3회 연속, FAULT는 ACK까지 래치) → UART·LED·FND.
 * 입력 실패(결측·지연·범위·고착·링크)는 NPU보다 먼저 규칙으로 판정하고, 그때 NPU는 실행하지 않는다.
 * LED15(경보)는 표시·기록용이다. 실제 위험 장치의 정지·인터록에 쓰지 않는다(6-4: 독립 보호 로직이 우선).
 * 같은 입력으로 CPU 정수 추론도 실행해 NPU 점수와 비교한다(불일치 = UNKNOWN).
 */
#include "app.h"
#include "npu_driver.h"
#include "sensor_app.h"
#include "sensor_io.h"
#include "sensor_model.h"

#define T_MISS  0x7FFF
#define V_MISS  0xFFFFu
#define D_MISS  0xFFFFu
#define STALE_MS 500u

#define FND_ON(m)    ((uint32_t)(m) << 16)
#define FND_DP3      (1u << 23)
#define LED_LATCH    (1u << 13)
#define LED_ERROR    (1u << 14)
#define LED_ALARM    (1u << 15)

static const int sev_of[4] = {0, 1, 3, 2};           /* 코드 → 심각도: NORMAL 0, WARNING 1, FAULT 3, UNKNOWN 2 */
static const int code_of[4] = {ST_NORMAL, ST_WARNING, ST_UNKNOWN, ST_FAULT};

static uint8_t rx_buf[SENSOR_PAYLOAD];
static int8_t x_buf[NPU_N_IN];                        /* x[0..5] = 특징, 나머지 0 */
static char score_txt[3 * 16], feat_txt[SENSOR_N_FEAT * 5];
static policy_t pol;
static int model_ok, bad_streak;

/* ------------------------------------------------------------ 정책 (sensor_reference.Policy와 같다) */
void policy_reset(policy_t *p)
{
    p->state = ST_UNKNOWN;
    p->latch = p->cnt = p->hold = 0;
}

void policy_cand(policy_t *p, int c)
{
    if (sev_of[c] >= sev_of[p->state]) {
        p->state = c;
        p->cnt = 0;
        if (c == ST_FAULT)
            p->latch = 1;
    } else if (p->latch) {
        p->cnt = 0;
    } else {
        p->hold = (p->cnt == 0 || sev_of[c] > p->hold) ? sev_of[c] : p->hold;
        if (p->cnt == POLICY_CLEAR_N - 1) {
            p->state = code_of[p->hold];
            p->cnt = 0;
        } else {
            p->cnt++;
        }
    }
}

int policy_ack(policy_t *p)
{
    if (!p->latch)
        return 0;
    p->latch = 0;
    p->cnt = 0;
    return 1;
}

/* ------------------------------------------------------------ guard·특징 */
void sensor_guard(const sensor_win_t *s, int *fmask, int *umask)
{
    int i, miss, bad, lo, hi;
    *fmask = *umask = 0;
    for (i = 0; i < 3; i++)
        if (s->age[i] > STALE_MS)
            *umask |= 1 << i;
    for (miss = bad = i = 0; i < SENSOR_WIN; i++) {
        miss |= s->t[i] == T_MISS;
        bad |= s->t[i] < -320 || s->t[i] > 1600;
    }
    if (miss)
        *umask |= B_T;
    else if (bad)
        *fmask |= B_T;
    for (miss = bad = 0, lo = hi = 1, i = 0; i < SENSOR_WIN; i++) {
        miss |= s->v[i] == V_MISS;
        bad |= s->v[i] > 4095u;
        lo &= s->v[i] <= 15u;
        hi &= s->v[i] >= 4080u;
    }
    if (miss)
        *umask |= B_V;
    else if (bad || lo || hi)
        *fmask |= B_V;
    for (miss = bad = i = 0; i < SENSOR_WIN; i++) {
        miss |= s->d[i] == D_MISS;
        bad |= s->d[i] < 2u || s->d[i] > 400u;
    }
    if (miss)
        *umask |= B_D;
    else if (bad)
        *fmask |= B_D;
}

static int8_t q(int32_t n, int32_t d)
{
    int32_t v;
    if (n <= 0)
        return 0;
    v = n * 127 / d;
    return (int8_t)(v > 127 ? 127 : v);
}

/* guard를 통과한 창만 넣는다(값이 유효 범위라 int32 곱셈이 넘치지 않는다) */
void sensor_features(const sensor_win_t *s, int8_t f[SENSOR_N_FEAT])
{
    int32_t tmax = s->t[0], vmax = s->v[0], vmin = s->v[0], dmin = s->d[0], vs = 0, mad = 0, mv;
    int i;
    for (i = 0; i < SENSOR_WIN; i++) {
        if (s->t[i] > tmax) tmax = s->t[i];
        if (s->v[i] > vmax) vmax = s->v[i];
        if (s->v[i] < vmin) vmin = s->v[i];
        if (s->d[i] < dmin) dmin = s->d[i];
        vs += s->v[i];
    }
    mv = vs / SENSOR_WIN;
    for (i = 0; i < SENSOR_WIN; i++)
        mad += s->v[i] > mv ? s->v[i] - mv : mv - s->v[i];
    f[0] = q(tmax - 720, 800);
    f[1] = q((int32_t)s->t[SENSOR_WIN - 1] - s->t[0] - 16, 160);
    f[2] = q(vmax - vmin - 400, 2200);
    f[3] = q(mad / SENSOR_WIN - 120, 760);
    f[4] = q(125 - dmin, 160);
    f[5] = q((int32_t)s->d[0] - s->d[SENSOR_WIN - 1] - 10, 120);
}

static uint32_t crc32_byte(uint32_t crc, uint8_t v)
{
    int b;
    crc ^= v;
    for (b = 0; b < 8; b++)
        crc = (crc & 1u) ? (crc >> 1) ^ 0xEDB88320u : crc >> 1;
    return crc;
}

/* zlib.crc32(w[10][784] ‖ b[10] int64 LE) — ROM 모델 = Python 모델 확인(6-1과 같은 규칙) */
uint32_t sensor_model_crc32(void)
{
    uint32_t crc = 0xFFFFFFFFu;
    int c, i;
    for (c = 0; c < NPU_N_CLASS; c++)
        for (i = 0; i < NPU_N_IN; i++)
            crc = crc32_byte(crc, (uint8_t)model_w[c][i]);
    for (c = 0; c < NPU_N_CLASS; c++) {
        uint64_t v = (uint64_t)model_b[c];
        for (i = 0; i < 8; i++)
            crc = crc32_byte(crc, (uint8_t)(v >> (8 * i)));
    }
    return ~crc;
}

static uint16_t crc16(const uint8_t *p, uint32_t n, uint16_t crc)
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

/* ------------------------------------------------------------ 출력 */
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

/* FND: [3] 상태 코드(점 = latch), [2] 이유 비트(digit2 < 0이면 끔), [1:0] seq 하위 바이트 또는 'E'+오류 코드 */
static void show(int digit2, uint32_t low, int err)
{
    uint32_t fnd = ((uint32_t)pol.state << 12) | (low & 0xFFu) | (pol.latch ? FND_DP3 : 0);
    uint32_t led = (1u << pol.state) | (pol.state != ST_NORMAL ? LED_ALARM : 0) | (pol.latch ? LED_LATCH : 0);
    if (digit2 >= 0)
        fnd |= ((uint32_t)digit2 << 8) | FND_ON(0xF);
    else
        fnd |= FND_ON(0xB);
    if (err) {
        fnd = (fnd & ~0xFFu) | (0xEu << 4) | (uint32_t)err;
        led |= LED_ERROR;
    }
    sio_display(fnd, led);
    APP_PRINTF("DISP fnd=%08x led=%04x\r\n", (unsigned)fnd, (unsigned)led);
    sio_flush();
}

/* 후보를 정책에 넣고 STATE 줄을 낸다. guard_name이 "OK"면 특징·점수 문자열을 함께 낸다. */
static void apply(const char *src, int seq, const char *guard_name, int fmask, int umask, int cand,
                  int npu, int cpu, int match, int junk, int with_disp)
{
    int ok = guard_name[0] == 'O';
    policy_cand(&pol, cand);
    APP_PRINTF("STATE src=%s seq=%d guard=%s fmask=%d umask=%d feat=%s npu=%d cpu=%d match=%d scores=%s "
               "cand=%d state=%d latch=%d cnt=%d junk=%d\r\n",
               src, seq, guard_name, fmask, umask, ok ? feat_txt : "-", npu, cpu, match, ok ? score_txt : "-",
               cand, pol.state, pol.latch, pol.cnt, junk);
    if (with_disp)
        show(fmask | umask, seq >= 0 ? (uint32_t)seq : 0u, 0);
}

static void proto_error(int seq, int code, const char *name, int detail, int junk)
{
    bad_streak++;
    APP_PRINTF("ERROR seq=%d code=%d name=%s detail=%d junk=%d bad=%d\r\n", seq, code, name, detail, junk, bad_streak);
    if (bad_streak >= LINK_BAD_N)                     /* 연속 프로토콜 오류 = 링크 이상 → UNKNOWN */
        apply("LINK_BAD", -1, "LINK", 0, B_LINK, ST_UNKNOWN, -1, -1, -1, junk, 0);
    show(-1, 0, code);
}

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

static void sensor_frame(npu_t *npu, int junk)
{
    sensor_win_t s;
    int64_t ns[NPU_N_CLASS], cs[NPU_N_CLASS];
    int seq = rx_buf[0] | (rx_buf[1] << 8);
    uint32_t mid = rx_buf[2] | ((uint32_t)rx_buf[3] << 8) | ((uint32_t)rx_buf[4] << 16) | ((uint32_t)rx_buf[5] << 24);
    const uint8_t *p = rx_buf + 6;
    int i, c, rc, fmask, umask, ncls = -1, ccls, same = 1;
    int8_t f[SENSOR_N_FEAT];
    char *o;
    if (mid != SENSOR_MODEL_ID || !model_ok) {
        proto_error(seq, SERR_MODEL, "MODEL", model_ok, junk);
        return;
    }
    bad_streak = 0;
    for (i = 0; i < 3; i++, p += 2)
        s.age[i] = (uint16_t)(p[0] | (p[1] << 8));
    for (i = 0; i < SENSOR_WIN; i++, p += 6) {
        s.t[i] = (int16_t)(uint16_t)(p[0] | (p[1] << 8));
        s.v[i] = (uint16_t)(p[2] | (p[3] << 8));
        s.d[i] = (uint16_t)(p[4] | (p[5] << 8));
    }
    sensor_guard(&s, &fmask, &umask);                 /* 1) 규칙 먼저: 실패면 NPU를 실행하지 않는다 */
    if (fmask || umask) {
        apply("FRAME", seq, fmask ? "FAULT" : "UNKNOWN", fmask, umask, fmask ? ST_FAULT : ST_UNKNOWN,
              -1, -1, -1, junk, 1);
        return;
    }
    sensor_features(&s, f);                           /* 2) 특징 → NPU */
    for (o = feat_txt, i = 0; i < SENSOR_N_FEAT; i++) {
        x_buf[i] = f[i];
        if (i)
            *o++ = ',';
        o = fmt_i64(o, f[i]);
    }
    *o = '\0';
    rc = npu_infer(npu, x_buf, model_w, ns, &ncls);
    if (rc != NPU_OK) {
        uint32_t st = npu_last_status(npu);
        npu_recover(npu);
        APP_PRINTF("ERROR seq=%d code=%d name=NPU detail=%d junk=%d bad=%d\r\n", seq, SERR_NPU,
                   (int)NPU_ST_ERR_CODE(st), junk, bad_streak);
        score_txt[0] = '-';
        score_txt[1] = '\0';
        apply("NPU", seq, "OK", 0, B_LINK, ST_UNKNOWN, -1, -1, 0, junk, 0);
        show(-1, 0, SERR_NPU);
        return;
    }
    npu_clear_done(npu);
    ccls = cpu_infer(x_buf, model_w, model_b, cs);    /* 3) CPU 대조 */
    for (o = score_txt, c = 0; c < SENSOR_N_CLS; c++) {
        if (c)
            *o++ = ',';
        o = fmt_i64(o, ns[c]);
    }
    *o = '\0';
    for (c = 0; c < NPU_N_CLASS; c++)
        if (ns[c] != cs[c])
            same = 0;
    if (ncls != ccls || ncls < 0 || ncls >= SENSOR_N_CLS)
        same = 0;
    if (!same) {
        APP_PRINTF("ERROR seq=%d code=%d name=MISMATCH detail=%d junk=%d bad=%d\r\n", seq, SERR_MISMATCH, ncls, junk,
                   bad_streak);
        apply("NPU", seq, "OK", 0, B_LINK, ST_UNKNOWN, ncls, ccls, 0, junk, 0);
        show(-1, 0, SERR_MISMATCH);
        return;
    }
    apply("FRAME", seq, "OK", 0, 0, ncls, ncls, ccls, 1, junk, 1);   /* 4) 후보 = NPU class */
}

/* 응답 1개 처리. 반환 0: 계속, -1: 입력 종료(PC) */
static int handle(npu_t *npu)
{
    int c, prev = -1, junk = 0, cmd;
    uint32_t i, len;
    uint16_t crc;
    uint8_t b;
    for (;;) {                                         /* 동기 'P' '3' 찾기 */
        c = sio_getc(SIO_WAIT_LINK);
        if (c == SIO_EOF)
            return -1;
        if (c == SIO_TIMEOUT) {                        /* 링크 감시: 센서 프레임 없음 → UNKNOWN */
            apply("LINK_TIMEOUT", -1, "LINK", 0, B_LINK, ST_UNKNOWN, -1, -1, -1, junk, 1);
            return 0;
        }
        if (prev == 'P' && c == '3')
            break;
        if (prev >= 0)
            junk++;
        prev = c;
    }
    cmd = sio_getc(SIO_IN_FRAME);
    if (cmd < 0) {
        proto_error(-1, SERR_TIMEOUT, "TIMEOUT", 0, junk);
        return cmd == SIO_EOF ? -1 : 0;
    }
    if (cmd == 'S')
        len = SENSOR_PAYLOAD;
    else if (cmd == 'I' || cmd == 'A')
        len = 0;
    else {
        while ((c = sio_getc(SIO_IN_FRAME)) >= 0)
            ;
        proto_error(-1, SERR_CMD, "CMD", cmd, junk);
        return c == SIO_EOF ? -1 : 0;
    }
    b = (uint8_t)cmd;
    crc = crc16(&b, 1, 0xFFFFu);
    for (i = 0; i < len + 2; i++) {
        c = sio_getc(SIO_IN_FRAME);
        if (c < 0) {
            proto_error(-1, SERR_TIMEOUT, "TIMEOUT", (int)i, junk);
            return c == SIO_EOF ? -1 : 0;
        }
        if (i < len)
            rx_buf[i] = (uint8_t)c;
        b = (uint8_t)c;
        crc = crc16(&b, 1, crc);
    }
    if (crc != 0) {
        proto_error(-1, SERR_CRC, "CRC", (int)len, junk);
        return 0;
    }
    if (cmd == 'I') {
        APP_PRINTF("P3_SENSOR READY model=%08x model_ok=%d feat=%d classes=%d junk=%d\r\n",
                   (unsigned)SENSOR_MODEL_ID, sensor_model_crc32() == SENSOR_MODEL_ID, SENSOR_N_FEAT, SENSOR_N_CLS, junk);
        sio_flush();
    } else if (cmd == 'A') {
        int ok = policy_ack(&pol);
        APP_PRINTF("ACK ok=%d state=%d latch=%d\r\n", ok, pol.state, pol.latch);
        show(-1, 0, 0);
    } else {
        sensor_frame(npu, junk);
    }
    return 0;
}

int sensor_app_run(uintptr_t npu_base)
{
    npu_t npu;
    int n = 0, rc;
    uint32_t mcrc = sensor_model_crc32();
    policy_reset(&pol);                                /* 안전한 기본값: 데이터를 보기 전에는 UNKNOWN */
    bad_streak = 0;
    npu_init(&npu, npu_base);
    rc = npu_set_bias(&npu, model_b);
    model_ok = mcrc == SENSOR_MODEL_ID && rc == NPU_OK;
    APP_PRINTF("P3_SENSOR READY model=%08x model_ok=%d feat=%d classes=%d bias_rc=%d\r\n",
               (unsigned)SENSOR_MODEL_ID, model_ok, SENSOR_N_FEAT, SENSOR_N_CLS, rc);
    show(-1, 0, 0);
    while (handle(&npu) == 0)
        n++;
    return n;
}
