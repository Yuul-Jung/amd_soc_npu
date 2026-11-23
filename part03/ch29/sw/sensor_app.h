/* 센서 융합 상태 감시 응용. 규약·규칙의 정본은 reference/sensor_reference.py 머리말. */
#ifndef SENSOR_APP_H
#define SENSOR_APP_H
#include <stdint.h>

#define SENSOR_WIN       8
#define SENSOR_N_FEAT    6
#define SENSOR_N_CLS     3
#define SENSOR_PAYLOAD   60          /* seq u16 + model_id u32 + age 3×u16 + 8×(t i16, v u16, d u16) */

enum { ST_NORMAL = 0, ST_WARNING = 1, ST_FAULT = 2, ST_UNKNOWN = 3 };
enum { B_T = 1, B_V = 2, B_D = 4, B_LINK = 8 };
enum { SERR_CRC = 1, SERR_TIMEOUT = 2, SERR_CMD = 3, SERR_MODEL = 4, SERR_NPU = 6, SERR_MISMATCH = 7 };

#define POLICY_CLEAR_N 3
#define LINK_BAD_N     3

typedef struct {
    int state, latch, cnt, hold;
} policy_t;

typedef struct {
    uint16_t age[3];
    int16_t t[SENSOR_WIN];
    uint16_t v[SENSOR_WIN], d[SENSOR_WIN];
} sensor_win_t;

void policy_reset(policy_t *p);
void policy_cand(policy_t *p, int cand);
int policy_ack(policy_t *p);
void sensor_guard(const sensor_win_t *s, int *fmask, int *umask);
void sensor_features(const sensor_win_t *s, int8_t f[SENSOR_N_FEAT]);
uint32_t sensor_model_crc32(void);
/* 프레임 처리 루프. PC 빌드는 입력이 끝나면 처리한 응답 수를 돌려준다(보드는 돌아오지 않음). */
int sensor_app_run(uintptr_t npu_base);

#endif
