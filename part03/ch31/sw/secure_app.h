/* (추가) 31장: 보안 UART 모델 적재 응용. 규격은 reference/secure_reference.py 머리말. */
#ifndef SECURE_APP_H
#define SECURE_APP_H
#include <stdint.h>
int secure_app_run(uintptr_t npu_base);   /* PC 빌드는 입력이 끝나면 처리 수를 돌려준다 */
#endif
