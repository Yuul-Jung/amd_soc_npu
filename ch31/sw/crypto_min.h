/* 31장 최소 암호 함수 (소프트웨어, MicroBlaze V에서 C로 실행): AES-128 암호화, CTR, SHA-256, HMAC-SHA256.
 * FPGA 암호 RTL은 만들지 않았다. 부채널(시간·전력) 대책이 없는 교육용 구현이다. */
#ifndef CRYPTO_MIN_H
#define CRYPTO_MIN_H
#include <stdint.h>
#include <stddef.h>

void aes128_encrypt_block(const uint8_t key[16], const uint8_t in[16], uint8_t out[16]);
void aes128_ctr(const uint8_t key[16], const uint8_t iv[16], const uint8_t *in, uint8_t *out, size_t n);

typedef struct { uint32_t h[8]; uint64_t len; uint8_t buf[64]; size_t used; } sha256_t;
void sha256_init(sha256_t *s);
void sha256_update(sha256_t *s, const uint8_t *p, size_t n);
void sha256_final(sha256_t *s, uint8_t out[32]);
void hmac_sha256(const uint8_t *key, size_t klen, const uint8_t *msg, size_t n, uint8_t out[32]);
int  ct_equal(const uint8_t *a, const uint8_t *b, size_t n);   /* 시간 일정 비교 */

#endif
