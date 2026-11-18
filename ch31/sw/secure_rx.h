/* 31장 인증 틀 수신: 'S' 형식 1 카운터4 길이2 | 암호문 | 태그16
 *  암호: AES-128-CTR, IV = 세션 Nonce 8바이트 ‖ 카운터 4바이트 ‖ 0 4바이트 (카운터가 겹치지 않으면 IV도 겹치지 않음)
 *  인증: HMAC-SHA256(머리 8바이트 ‖ 암호문)의 앞 16바이트 (암호화 뒤 인증)
 *  순서: 카운터가 마지막으로 받아들인 값보다 커야 함(재전송 거부) → 태그 확인 → 그 뒤에만 카운터 갱신·복호 */
#ifndef SECURE_RX_H
#define SECURE_RX_H
#include <stdint.h>
#include <stddef.h>

#define SF_MODEL_CHUNK  1
#define SF_MODEL_COMMIT 2
#define SF_IMAGE        3
#define SF_MODEL_BYTES  (7840 + 40)          /* INT8 가중치 10×784 + Bias 10×4 (리틀 엔디언) */

typedef enum { SR_OK_CHUNK = 1, SR_OK_COMMIT = 2, SR_OK_IMAGE = 3,
               SR_ERR_FORMAT = -1, SR_ERR_REPLAY = -2, SR_ERR_MAC = -3, SR_ERR_COMMIT = -4 } sr_result_t;

typedef struct {
    const uint8_t *k_enc, *k_mac, *nonce;    /* 키 16·16바이트, Nonce 8바이트 */
    uint32_t last_ctr;
    uint8_t  staging[SF_MODEL_BYTES], active[SF_MODEL_BYTES];
    uint8_t  got[(SF_MODEL_BYTES + 7) / 8];   /* 받은 바이트 표시 */
    uint8_t  image[784];
    uint32_t commits;
} secure_rx_t;

void        srx_init(secure_rx_t *s, const uint8_t *k_enc, const uint8_t *k_mac, const uint8_t *nonce);
sr_result_t srx_frame(secure_rx_t *s, const uint8_t *f, size_t n);

#endif
