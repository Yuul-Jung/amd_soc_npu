/* (추가) 30장: NPU 추천 + 독립 모터 안전 코어 응용. 규칙 정본은 reference/motor_reference.py·rtl/p3_motor_safety.v. */
#ifndef MOTOR_APP_H
#define MOTOR_APP_H
#include <stdint.h>

#define M_STOP 0
#define M_FWD  1
#define M_REV  2

/* 명령 워드(모터 GPIO axi_gpio_motor 채널 1, 안 A 0x4007_0000): [6:0] duty, [9:8] dir, [12] clear 토글, [15] kick 토글 */
#define MOTOR_CMD(dir, duty, kick, clr) \
    ((uint32_t)(duty) | ((uint32_t)(dir) << 8) | ((uint32_t)(clr) << 12) | ((uint32_t)(kick) << 15))
#define MOTOR_REG_CMD    0x0u   /* AXI GPIO 채널 1 DATA */
#define MOTOR_REG_STATUS 0x8u   /* AXI GPIO 채널 2 DATA */

/* 상태 워드 필드 */
#define MST_DUTY(s)    ((s) & 0x7Fu)
#define MST_DRIVE(s)   (((s) >> 8) & 3u)
#define MST_TRIP(s)    (((s) >> 14) & 1u)

/* 추천: 29장 정책 상태 → (방향, 속도). NORMAL 80 %, WARNING 30 %, FAULT·UNKNOWN STOP */
void motor_recommend(int state, int op_dir, int *dir, int *duty);
/* inject_base: PC 협동 시뮬레이션의 시험 주입 주소(보드 빌드에서는 0 = 'J' 명령 거부) */
int motor_app_run(uintptr_t npu_base, uintptr_t motor_base, uintptr_t inject_base);

#endif
