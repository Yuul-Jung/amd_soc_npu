/* (추가) 31장: 교육용 AES-128(암호화 방향)·CTR, SHA-256, HMAC-SHA-256, 일정시간 비교. 부채널 대책 없음. */
#ifndef P3_CRYPTO_H
#define P3_CRYPTO_H
#include <stdint.h>

void aes128_encrypt_block(const uint8_t key[16], const uint8_t in[16], uint8_t out[16]);
/* CTR(SP 800-38A): iv의 마지막 32비트(BE)를 블록마다 1 증가. 암호화·복호가 같은 연산 */
void aes128_ctr(const uint8_t key[16], const uint8_t iv[16], const uint8_t *in, uint8_t *out, uint32_t n);

typedef struct {
    uint32_t h[8];
    uint64_t len;
    uint8_t buf[64];
    uint32_t fill;
} sha256_t;
void sha256_init(sha256_t *s);
void sha256_update(sha256_t *s, const uint8_t *p, uint32_t n);
void sha256_final(sha256_t *s, uint8_t out[32]);
/* key ≤ 64바이트. 메시지를 두 조각(a, b)으로 받아 복사 없이 계산 */
void hmac_sha256(const uint8_t *key, uint32_t klen, const uint8_t *a, uint32_t na, const uint8_t *b, uint32_t nb,
                 uint8_t out[32]);
/* 일정시간 비교: 모든 바이트를 끝까지 비교하고 차이를 OR로 모은다(앞에서 멈추지 않음). 같으면 1 */
int ct_equal(const uint8_t *a, const uint8_t *b, uint32_t n);

#endif
