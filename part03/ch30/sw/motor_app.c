/* NPU 추천 → 독립 모터 안전 코어. 6-3 센서 감시(guard·특징·NPU·경보 정책)를 그대로 재사용하고
 * (6-3 sensor_app.c를 수정 없이 링크), 정책 상태를 방향·속도 추천으로 바꿔 명령 워드로만 쓴다.
 * CPU는 IN1/IN2/ENA를 직접 구동하지 않는다. E-Stop·고장·과열·워치독·트립·리밋은 RTL 코어가 AI 결과와 무관하게 우선한다.
 * 명령을 쓸 때마다 kick 비트를 토글한다(워치독 갱신). 센서 프레임이 멈추면 kick도 멈추고 코어가 정지·트립한다.
 * 트립 해제('C')는 운전자 명령이며 STOP 명령을 먼저 쓴 뒤 다음 쓰기에서 clear 비트를 토글한다.
 */
#include "app.h"
#include "npu_driver.h"
#include "sensor_app.h"
#include "sensor_io.h"
#include "sensor_model.h"
#include "motor_app.h"

#define FND_ON(m)  ((uint32_t)(m) << 16)
#define LED_LATCH  (1u << 13)
#define LED_ERROR  (1u << 14)
#define LED_ALARM  (1u << 15)

static uint8_t rx_buf[SENSOR_PAYLOAD];
static int8_t x_buf[NPU_N_IN];
static policy_t pol;
static uintptr_t mbase, ibase;
static int kick, clr, op_dir = M_FWD, rec_dir, rec_duty, model_ok, bad_streak;

void motor_recommend(int state, int op, int *dir, int *duty)
{
    if (state == ST_NORMAL || state == ST_WARNING) {
        *dir = op;
        *duty = state == ST_NORMAL ? 80 : 30;
    } else {
        *dir = M_STOP;
        *duty = 0;
    }
}

static void motor_write(void)
{
    kick ^= 1;
    npu_io_write(mbase + MOTOR_REG_CMD, MOTOR_CMD(rec_dir, rec_duty, kick, clr));
}

static void command_from_policy(void)
{
    motor_recommend(pol.state, op_dir, &rec_dir, &rec_duty);
    motor_write();
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

/* FND: [3] 정책 상태, [2] 실제 구동 방향(점 = 모터 트립), [1:0] 실제 duty(16진). LED는 CPU 몫만(9..12는 Top이 핀 표시) */
static void show(uint32_t st, int err)
{
    uint32_t fnd = ((uint32_t)pol.state << 12) | (MST_DRIVE(st) << 8) | MST_DUTY(st) | FND_ON(0xF)
                   | (MST_TRIP(st) ? (1u << 22) : 0);
    uint32_t led = (1u << pol.state) | (pol.state != ST_NORMAL ? LED_ALARM : 0) | (pol.latch ? LED_LATCH : 0)
                   | (err ? LED_ERROR : 0);
    sio_display(fnd, led);
    APP_PRINTF("DISP fnd=%08x led=%04x\r\n", (unsigned)fnd, (unsigned)led);
    sio_flush();
}

static void report(const char *src, int seq, const char *guard, int npu, int ok, int junk)
{
    uint32_t st = npu_io_read(mbase + MOTOR_REG_STATUS);
    APP_PRINTF("MOTOR src=%s seq=%d guard=%s npu=%d state=%d latch=%d ok=%d op_dir=%d rec_dir=%d rec_duty=%d st=%08x junk=%d\r\n",
               src, seq, guard, npu, pol.state, pol.latch, ok, op_dir, rec_dir, rec_duty, (unsigned)st, junk);
    show(st, 0);
}

static void proto_error(int seq, int code, const char *name, int detail, int junk)
{
    bad_streak++;
    APP_PRINTF("ERROR seq=%d code=%d name=%s detail=%d junk=%d bad=%d\r\n", seq, code, name, detail, junk, bad_streak);
    if (bad_streak >= LINK_BAD_N) {                    /* 연속 프로토콜 오류 = 링크 이상 → UNKNOWN → STOP 추천 */
        policy_cand(&pol, ST_UNKNOWN);
        command_from_policy();
    }
    show(npu_io_read(mbase + MOTOR_REG_STATUS), 1);
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
    sensor_guard(&s, &fmask, &umask);                 /* 6-3: 규칙 먼저 */
    if (fmask || umask) {
        policy_cand(&pol, fmask ? ST_FAULT : ST_UNKNOWN);
        command_from_policy();
        report("FRAME", seq, fmask ? "FAULT" : "UNKNOWN", -1, -1, junk);
        return;
    }
    sensor_features(&s, f);
    for (i = 0; i < SENSOR_N_FEAT; i++)
        x_buf[i] = f[i];
    rc = npu_infer(npu, x_buf, model_w, ns, &ncls);
    if (rc == NPU_OK) {
        npu_clear_done(npu);
        ccls = cpu_infer(x_buf, model_w, model_b, cs);
        for (c = 0; c < NPU_N_CLASS; c++)
            same &= ns[c] == cs[c];
        same &= ncls == ccls && ncls >= 0 && ncls < SENSOR_N_CLS;
    }
    if (rc != NPU_OK || !same) {                       /* NPU 오류·불일치 = UNKNOWN → STOP 추천 */
        APP_PRINTF("ERROR seq=%d code=%d name=%s detail=%d junk=%d bad=%d\r\n", seq,
                   rc != NPU_OK ? SERR_NPU : SERR_MISMATCH, rc != NPU_OK ? "NPU" : "MISMATCH", rc, junk, bad_streak);
        policy_cand(&pol, ST_UNKNOWN);
        command_from_policy();
        report("NPU", seq, "OK", ncls, -1, junk);
        return;
    }
    policy_cand(&pol, ncls);
    command_from_policy();
    report("FRAME", seq, "OK", ncls, -1, junk);
}

/* 'J' 시험 주입(PC 시뮬레이션 전용): op 1 = 입력 비트 {lim_r, lim_f, otemp, fault, estop}, op 2 = N클록 진행 */
static void inject(int junk)
{
    int op = rx_buf[0];
    uint32_t v = rx_buf[1] | ((uint32_t)rx_buf[2] << 8) | ((uint32_t)rx_buf[3] << 16) | ((uint32_t)rx_buf[4] << 24);
    if (!ibase || (op != 1 && op != 2)) {
        proto_error(-1, SERR_CMD, "CMD", 'J', junk);
        return;
    }
    npu_io_write(ibase + (op == 1 ? 0x0u : 0x4u), v);
    report(op == 1 ? "INJECT" : "ADVANCE", -1, "-", -1, -1, junk);
}

static int handle(npu_t *npu)
{
    int c, prev = -1, junk = 0, cmd;
    uint32_t i, len;
    uint16_t crc;
    uint8_t b;
    for (;;) {
        c = sio_getc(SIO_WAIT_LINK);
        if (c == SIO_EOF)
            return -1;
        if (c == SIO_TIMEOUT) {                        /* 센서 프레임 없음 → UNKNOWN → STOP 추천 */
            policy_cand(&pol, ST_UNKNOWN);
            command_from_policy();
            report("LINK_TIMEOUT", -1, "LINK", -1, -1, junk);
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
    else if (cmd == 'D')
        len = 1;
    else if (cmd == 'J')
        len = 5;
    else if (cmd == 'I' || cmd == 'A' || cmd == 'C' || cmd == 'Q')
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
    switch (cmd) {
    case 'I':
        APP_PRINTF("P3_MOTOR READY model=%08x model_ok=%d junk=%d\r\n", (unsigned)SENSOR_MODEL_ID,
                   sensor_model_crc32() == SENSOR_MODEL_ID, junk);
        sio_flush();
        break;
    case 'S':
        sensor_frame(npu, junk);
        break;
    case 'D':                                          /* 운전자 방향(1 FWD, 2 REV). 속도는 계속 정책 상태가 정한다 */
        if (rx_buf[0] != M_FWD && rx_buf[0] != M_REV) {
            proto_error(-1, SERR_CMD, "DIR", rx_buf[0], junk);
            break;
        }
        op_dir = rx_buf[0];
        command_from_policy();
        report("DIR", -1, "-", -1, -1, junk);
        break;
    case 'A':                                          /* 6-3 경보 래치 ACK(모터 트립 해제가 아니다) */
        c = policy_ack(&pol);
        report("ACK", -1, "-", -1, c, junk);
        break;
    case 'C':                                          /* 모터 트립 해제: STOP 쓰기 → 다음 쓰기에서 clear 토글 */
        rec_dir = M_STOP;
        rec_duty = 0;
        motor_write();
        clr ^= 1;
        npu_io_write(mbase + MOTOR_REG_CMD, MOTOR_CMD(rec_dir, rec_duty, kick, clr));
        report("CLEAR", -1, "-", -1, -1, junk);
        break;
    case 'Q':                                          /* 상태 조회: 명령을 쓰지 않는다(워치독 갱신 없음) */
        report("QUERY", -1, "-", -1, -1, junk);
        break;
    default:
        inject(junk);
        break;
    }
    return 0;
}

int motor_app_run(uintptr_t npu_base, uintptr_t motor_base, uintptr_t inject_base)
{
    npu_t npu;
    int n = 0, rc;
    uint32_t mcrc = sensor_model_crc32();
    mbase = motor_base;
    ibase = inject_base;
    policy_reset(&pol);                                /* 6-3: 부팅 UNKNOWN → 추천 STOP */
    motor_recommend(pol.state, op_dir, &rec_dir, &rec_duty);
    npu_io_write(mbase + MOTOR_REG_CMD, MOTOR_CMD(rec_dir, rec_duty, kick, clr));   /* kick 토글 없음: 명령 아님 */
    npu_init(&npu, npu_base);
    rc = npu_set_bias(&npu, model_b);
    model_ok = mcrc == SENSOR_MODEL_ID && rc == NPU_OK;
    APP_PRINTF("P3_MOTOR READY model=%08x model_ok=%d bias_rc=%d\r\n", (unsigned)SENSOR_MODEL_ID, model_ok, rc);
    report("BOOT", -1, "-", -1, -1, 0);
    while (handle(&npu) == 0)
        n++;
    return n;
}
