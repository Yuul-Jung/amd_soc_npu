/* 31장 PC 시험: 공개 표준 시험 벡터로 C 암호 함수 확인 */
#include <stdio.h>
#include <string.h>
#include "crypto_min.h"
static int hexeq(const uint8_t *b, const char *hex, size_t n)
{
    char s[3]; for (size_t i = 0; i < n; i++) { snprintf(s, 3, "%02x", b[i]); if (memcmp(s, hex + 2 * i, 2)) return 0; } return 1;
}
static void unhex(const char *h, uint8_t *b, size_t n) { for (size_t i = 0; i < n; i++) sscanf(h + 2 * i, "%2hhx", &b[i]); }
int main(void)
{
    int f = 0; uint8_t k[16], p[64], o[64], d[32]; sha256_t s;
    unhex("000102030405060708090a0b0c0d0e0f", k, 16); unhex("00112233445566778899aabbccddeeff", p, 16);
    aes128_encrypt_block(k, p, o); f += !hexeq(o, "69c4e0d86a7b0430d8cdb78070b4c55a", 16);              /* FIPS-197 C.1 */
    unhex("2b7e151628aed2a6abf7158809cf4f3c", k, 16); uint8_t iv[16]; unhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", iv, 16);
    unhex("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51", p, 32);
    aes128_ctr(k, iv, p, o, 32); f += !hexeq(o, "874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff", 32);  /* SP 800-38A F.5.1 */
    sha256_init(&s); sha256_update(&s, (const uint8_t *)"abc", 3); sha256_final(&s, d);
    f += !hexeq(d, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", 32);                         /* FIPS 180-2 B.1 */
    memset(k, 0x0b, 16); uint8_t k20[20]; memset(k20, 0x0b, 20);
    hmac_sha256(k20, 20, (const uint8_t *)"Hi There", 8, d);
    f += !hexeq(d, "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", 32);                         /* RFC 4231 TC1 */
    printf(f ? "CRYPTO_VECTOR_TEST_FAIL fails=%d\n" : "CRYPTO_VECTOR_TEST_PASS vectors=4 (FIPS-197 C.1, SP800-38A F.5.1, SHA-256 abc, RFC4231 TC1)\n", f);
    return f != 0;
}
