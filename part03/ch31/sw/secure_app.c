/* 보안 UART 모델 적재 + 추론. 규격의 정본은 reference/secure_reference.py 머리말.
 *   'M' 보안 모델 프레임: CRC16(전송) → ver → len ≤ 256 → HMAC 검증(일정시간) → seq > last_seq → iv 결속
 *       → last_seq 소비 → AES-CTR 복호(스테이징 뱅크) → 모델 검사 → 원자적 커밋(활성 뱅크 전환 + NPU Bias 재적재)
 *       MAC 확인 전에는 복호하지 않고, 검사·커밋이 실패하면 활성 모델은 그대로다.
 *   'S' 추론(6-3 센서 창, guard·특징 재사용): 프레임의 model_id가 활성 모델과 같아야 한다.
 *   'I' 식별(활성 모델·키 지문·last_seq). 키 값은 출력하지 않는다.
 * 키는 build/secure_keys.h(저장소 제외)에만 있다. 교육용: Basys3에는 키 보호 저장소·Secure Boot·Tamper 방어가 없다.
 * last_seq는 RAM에만 있어 Reset 뒤 0으로 돌아간다(재부팅 뒤 Replay 가능 — 알려진 한계, README 참조).
 */
#include "app.h"
#include "npu_driver.h"
#include "sensor_app.h"
#include "sensor_io.h"
#include "secure_keys.h"
#include "p3_crypto.h"
#include "secure_app.h"

#define MAX_LEN   256u
#define HDR_LEN   27u                 /* ver 1 + seq 4 + model_id 4 + iv 16 + len 2 */
#define BLOB_LEN  54u
#define FND_ON(m) ((uint32_t)(m) << 16)

enum { R_VERSION = 1, R_LENGTH, R_AUTH, R_REPLAY, R_NONCE, R_MODEL, R_COMMIT };
static const char *const rname[] = {"", "VERSION", "LENGTH", "AUTH", "REPLAY", "NONCE", "MODEL", "COMMIT"};

typedef struct {
    uint32_t id;
    int8_t w[SENSOR_N_CLS][SENSOR_N_FEAT];
    int64_t b[SENSOR_N_CLS];
} model_bank_t;

static model_bank_t bank[2];          /* bank[active] = 사용 중, bank[!active] = 스테이징 */
static int active;
static int8_t w_exp[NPU_N_CLASS][NPU_N_IN];   /* 활성 뱅크에서 만든 5-1 IP 형태(나머지 0) */
static int64_t b_exp[NPU_N_CLASS];
static uint32_t last_seq;
static int last_reject;
static uint8_t rx[HDR_LEN + MAX_LEN + 32], plain[MAX_LEN];
static int8_t x_buf[NPU_N_IN];
static char score_txt[3 * 16];

static uint32_t rd32(const uint8_t *p) { return p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }

static uint32_t crc32_byte(uint32_t crc, uint8_t v)
{
    int b;
    crc ^= v;
    for (b = 0; b < 8; b++)
        crc = (crc & 1u) ? (crc >> 1) ^ 0xEDB88320u : crc >> 1;
    return crc;
}

/* 6-3 MODEL_ID 규칙: 5-1 IP 형태 w[10][784] ‖ b[10](int64 LE)의 CRC32. 빈 칸은 0, 쓰지 않는 Bias는 -2^38 */
static uint32_t bank_id(const model_bank_t *m)
{
    uint32_t crc = 0xFFFFFFFFu;
    int c, i;
    for (c = 0; c < NPU_N_CLASS; c++)
        for (i = 0; i < NPU_N_IN; i++)
            crc = crc32_byte(crc, (uint8_t)(c < SENSOR_N_CLS && i < SENSOR_N_FEAT ? m->w[c][i] : 0));
    for (c = 0; c < NPU_N_CLASS; c++) {
        uint64_t v = (uint64_t)(c < SENSOR_N_CLS ? m->b[c] : -((int64_t)1 << 38));
        for (i = 0; i < 8; i++)
            crc = crc32_byte(crc, (uint8_t)(v >> (8 * i)));
    }
    return ~crc;
}

/* 평문 blob → 뱅크(스테이징 검사). 성공 1 */
static int parse_blob(const uint8_t *p, uint32_t n, model_bank_t *m)
{
    int c, i;
    if (n != BLOB_LEN || p[0] != 'P' || p[1] != '3' || p[2] != 'M' || p[3] != 'D')
        return 0;
    if ((p[4] | (p[5] << 8)) != 1 || p[6] != SENSOR_N_CLS || p[7] != SENSOR_N_FEAT)
        return 0;
    for (c = 0; c < SENSOR_N_CLS; c++)
        for (i = 0; i < SENSOR_N_FEAT; i++) {
            m->w[c][i] = (int8_t)p[12 + SENSOR_N_FEAT * c + i];
            if (m->w[c][i] == -128)                          /* 대칭 양자화 범위 -127..127 */
                return 0;
        }
    for (c = 0; c < SENSOR_N_CLS; c++) {
        uint64_t v = 0;
        for (i = 7; i >= 0; i--)
            v = (v << 8) | p[30 + 8 * c + i];
        m->b[c] = (int64_t)v;
        if (m->b[c] < -((int64_t)1 << 39) || m->b[c] >= ((int64_t)1 << 39))   /* 5-1 Bias 40비트 */
            return 0;
    }
    m->id = bank_id(m);
    return m->id == rd32(p + 8);
}

static void expand(const model_bank_t *m)
{
    int c, i;
    for (c = 0; c < NPU_N_CLASS; c++) {
        for (i = 0; i < SENSOR_N_FEAT; i++)
            w_exp[c][i] = c < SENSOR_N_CLS ? m->w[c][i] : 0;
        b_exp[c] = c < SENSOR_N_CLS ? m->b[c] : -((int64_t)1 << 38);
    }
}

static void show(void)
{
    uint32_t fnd = ((bank[active].id >> 16) & 0xFFFFu) | FND_ON(0xF);
    uint32_t led = (uint32_t)active | (last_reject ? (1u << 14) : 0) | (SECURE_TEST_KEY ? (1u << 13) : 0);
    sio_display(fnd, led);
    APP_PRINTF("DISP fnd=%08x led=%04x\r\n", (unsigned)fnd, (unsigned)led);
    sio_flush();
}

static void reject(int r, uint32_t seq)
{
    last_reject = r;
    APP_PRINTF("SECURE result=REJECT reason=%s code=%d seq=%d last_seq=%d active=%08x\r\n", rname[r], r, (int)seq,
               (int)last_seq, (unsigned)bank[active].id);
    show();
}

static void error_line(const char *name, int code, int detail)
{
    APP_PRINTF("ERROR code=%d name=%s detail=%d active=%08x\r\n", code, name, detail, (unsigned)bank[active].id);
    show();
}

/* rx = 헤더 + 암호문 + 태그(CRC 통과). 처리 순서가 규격이다. */
static void secure_load(npu_t *npu, uint32_t len)
{
    uint8_t tag[32];
    const uint8_t *iv = rx + 9;
    uint32_t seq = rd32(rx + 1), mid = rd32(rx + 5), ivseq, ivctr;
    int st = !active, rc;
    if (rx[0] != 1) {
        reject(R_VERSION, seq);
        return;
    }
    hmac_sha256(mac_key, 32, (const uint8_t *)"P3SM", 4, rx, HDR_LEN + len, tag);
    if (!ct_equal(tag, rx + HDR_LEN + len, 32)) {     /* 인증 전에는 복호·시퀀스 소비 없음 */
        reject(R_AUTH, seq);
        return;
    }
    if (seq <= last_seq) {
        reject(R_REPLAY, seq);
        return;
    }
    ivseq = ((uint32_t)iv[8] << 24) | ((uint32_t)iv[9] << 16) | ((uint32_t)iv[10] << 8) | iv[11];
    ivctr = ((uint32_t)iv[12] << 24) | ((uint32_t)iv[13] << 16) | ((uint32_t)iv[14] << 8) | iv[15];
    if (ivseq != seq || ivctr != 0) {                  /* 같은 키에서 Nonce 재사용 금지: seq에 결속 */
        reject(R_NONCE, seq);
        return;
    }
    last_seq = seq;                                    /* 인증된 메시지는 내용이 틀려도 다시 쓰지 못하게 소비 */
    aes128_ctr(enc_key, iv, rx + HDR_LEN, plain, len);
    if (!parse_blob(plain, len, &bank[st]) || bank[st].id != mid) {
        reject(R_MODEL, seq);
        return;
    }
    expand(&bank[st]);                                 /* 커밋: 새 뱅크로 IP 형태를 만들고 Bias 적재 */
    rc = npu_set_bias(npu, b_exp);
    if (rc != NPU_OK) {                                /* 실패: 이전 뱅크로 되돌린다 */
        expand(&bank[active]);
        npu_set_bias(npu, b_exp);
        reject(R_COMMIT, seq);
        return;
    }
    active = st;
    last_reject = 0;
    APP_PRINTF("SECURE result=COMMIT seq=%d model=%08x bank=%d last_seq=%d\r\n", (int)seq, (unsigned)bank[active].id,
               active, (int)last_seq);
    show();
}

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

static void infer(npu_t *npu)
{
    sensor_win_t s;
    int64_t ns[NPU_N_CLASS], cs[NPU_N_CLASS];
    const uint8_t *p = rx + 6;
    int seq = rx[0] | (rx[1] << 8), i, c, fm, um, ncls = -1, ccls = -1, rc, same = 1;
    int8_t f[SENSOR_N_FEAT];
    char *o = score_txt;
    if (rd32(rx + 2) != bank[active].id) {
        error_line("MODEL", 4, seq);
        return;
    }
    for (i = 0; i < 3; i++, p += 2)
        s.age[i] = (uint16_t)(p[0] | (p[1] << 8));
    for (i = 0; i < SENSOR_WIN; i++, p += 6) {
        s.t[i] = (int16_t)(uint16_t)(p[0] | (p[1] << 8));
        s.v[i] = (uint16_t)(p[2] | (p[3] << 8));
        s.d[i] = (uint16_t)(p[4] | (p[5] << 8));
    }
    sensor_guard(&s, &fm, &um);
    if (fm || um) {
        APP_PRINTF("INFER seq=%d model=%08x guard=%s npu=-1 cpu=-1 match=-1 scores=-\r\n", seq,
                   (unsigned)bank[active].id, fm ? "FAULT" : "UNKNOWN");
        show();
        return;
    }
    sensor_features(&s, f);
    for (i = 0; i < SENSOR_N_FEAT; i++)
        x_buf[i] = f[i];
    rc = npu_infer(npu, x_buf, (const int8_t (*)[NPU_N_IN])w_exp, ns, &ncls);
    if (rc == NPU_OK) {
        npu_clear_done(npu);
        ccls = cpu_infer(x_buf, (const int8_t (*)[NPU_N_IN])w_exp, b_exp, cs);
        for (c = 0; c < NPU_N_CLASS; c++)
            same &= ns[c] == cs[c];
        same &= ncls == ccls;
    } else {
        same = 0;
    }
    for (c = 0; c < SENSOR_N_CLS; c++) {
        if (c)
            *o++ = ',';
        o = fmt_i64(o, rc == NPU_OK ? ns[c] : 0);
    }
    *o = '\0';
    APP_PRINTF("INFER seq=%d model=%08x guard=OK npu=%d cpu=%d match=%d scores=%s\r\n", seq,
               (unsigned)bank[active].id, ncls, ccls, same, score_txt);
    show();
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

/* n바이트를 rx+off에 받으며 CRC 누적. 실패 시 SIO_TIMEOUT/SIO_EOF */
static int recv(uint32_t off, uint32_t n, uint16_t *crc)
{
    uint32_t i;
    int c;
    uint8_t b;
    for (i = 0; i < n; i++) {
        c = sio_getc(SIO_IN_FRAME);
        if (c < 0)
            return c;
        b = (uint8_t)c;
        rx[off + i] = b;
        *crc = crc16(&b, 1, *crc);
    }
    return 0;
}

static int handle(npu_t *npu)
{
    int c, prev = -1, cmd, rc;
    uint16_t crc;
    uint8_t b;
    uint32_t len = 0;
    for (;;) {
        c = sio_getc(SIO_WAIT_LINK);
        if (c == SIO_EOF)
            return -1;
        if (c == SIO_TIMEOUT)
            continue;                                  /* 6-5는 링크 감시 동작 없음(대기 계속) */
        if (prev == 'P' && c == '3')
            break;
        prev = c;
    }
    cmd = sio_getc(SIO_IN_FRAME);
    if (cmd < 0) {
        error_line("TIMEOUT", 2, 0);
        return cmd == SIO_EOF ? -1 : 0;
    }
    b = (uint8_t)cmd;
    crc = crc16(&b, 1, 0xFFFFu);
    if (cmd == 'M') {
        rc = recv(0, HDR_LEN, &crc);
        if (rc == 0) {
            len = rx[25] | ((uint32_t)rx[26] << 8);
            if (len > MAX_LEN) {                       /* 버퍼 넘침 방지: 나머지는 끊길 때까지 버린다 */
                while ((c = sio_getc(SIO_IN_FRAME)) >= 0)
                    ;
                reject(R_LENGTH, rd32(rx + 1));
                return c == SIO_EOF ? -1 : 0;
            }
            rc = recv(HDR_LEN, len + 32, &crc);
        }
    } else if (cmd == 'S') {
        rc = recv(0, SENSOR_PAYLOAD, &crc);
    } else if (cmd == 'I') {
        rc = 0;
    } else {
        while ((c = sio_getc(SIO_IN_FRAME)) >= 0)
            ;
        error_line("CMD", 3, cmd);
        return c == SIO_EOF ? -1 : 0;
    }
    if (rc == 0) {
        uint8_t t[2];
        for (c = 0; c < 2 && rc == 0; c++) {
            int v = sio_getc(SIO_IN_FRAME);
            if (v < 0)
                rc = v;
            else {
                t[c] = (uint8_t)v;
                crc = crc16(&t[c], 1, crc);
            }
        }
    }
    if (rc < 0) {                                      /* 끊긴 프레임: 아무것도 반영하지 않는다 */
        error_line("TIMEOUT", 2, 0);
        return rc == SIO_EOF ? -1 : 0;
    }
    if (crc != 0) {
        error_line("CRC", 1, 0);
        return 0;
    }
    if (cmd == 'M')
        secure_load(npu, len);
    else if (cmd == 'S')
        infer(npu);
    else {
        APP_PRINTF("P3_SECURE READY model=%08x key_fp=%08x test_key=%d last_seq=%d\r\n", (unsigned)bank[active].id,
                   (unsigned)SECURE_KEY_FP, SECURE_TEST_KEY, (int)last_seq);
        sio_flush();
    }
    return 0;
}

int secure_app_run(uintptr_t npu_base)
{
    npu_t npu;
    int n = 0, ok, rc;
    npu_init(&npu, npu_base);
    active = 0;
    ok = parse_blob(model_a_blob, BLOB_LEN, &bank[0]) && bank[0].id == MODEL_A_ID;
    expand(&bank[0]);
    rc = npu_set_bias(&npu, b_exp);
    APP_PRINTF("P3_SECURE READY model=%08x model_ok=%d bias_rc=%d key_fp=%08x test_key=%d last_seq=%d\r\n",
               (unsigned)bank[0].id, ok, rc, (unsigned)SECURE_KEY_FP, SECURE_TEST_KEY, (int)last_seq);
    show();
    while (handle(&npu) == 0)
        n++;
    return n;
}
