/* (추가) 31장: C 암호 구현 알려진 정답 시험(PC). FIPS 197 C.1, SP 800-38A F.5.1(2블록), FIPS 180-4 "abc"·448비트,
 * RFC 4231 HMAC 1·2. 모두 맞으면 C_CRYPTO_KAT_PASS. */
#include <stdio.h>
#include <string.h>
#include "p3_crypto.h"

static void hex(const char *s, uint8_t *o) { while (*s) { sscanf(s, "%2hhx", o++); s += 2; } }

static int check(const char *name, const uint8_t *got, const char *exp_hex, int n)
{
    uint8_t e[64];
    hex(exp_hex, e);
    if (memcmp(got, e, (size_t)n)) { printf("C_CRYPTO_KAT_FAIL %s\n", name); return 1; }
    return 0;
}

int main(void)
{
    uint8_t k[32], p[64], o[64], iv[16];
    sha256_t s;
    int f = 0;
    hex("000102030405060708090a0b0c0d0e0f", k); hex("00112233445566778899aabbccddeeff", p);
    aes128_encrypt_block(k, p, o); f |= check("aes_c1", o, "69c4e0d86a7b0430d8cdb78070b4c55a", 16);
    hex("2b7e151628aed2a6abf7158809cf4f3c", k); hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", iv);
    hex("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51", p);
    aes128_ctr(k, iv, p, o, 32);
    f |= check("ctr_f51", o, "874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff", 32);
    sha256_init(&s); sha256_update(&s, (const uint8_t *)"abc", 3); sha256_final(&s, o);
    f |= check("sha_abc", o, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", 32);
    sha256_init(&s);
    sha256_update(&s, (const uint8_t *)"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56);
    sha256_final(&s, o);
    f |= check("sha_448", o, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", 32);
    memset(k, 0x0b, 20);
    hmac_sha256(k, 20, (const uint8_t *)"Hi ", 3, (const uint8_t *)"There", 5, o);
    f |= check("hmac_4231_1", o, "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", 32);
    hmac_sha256((const uint8_t *)"Jefe", 4, (const uint8_t *)"what do ya want for nothing?", 28, NULL, 0, o);
    f |= check("hmac_4231_2", o, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", 32);
    f |= !ct_equal(o, o, 32) || ct_equal((const uint8_t *)"ab", (const uint8_t *)"ac", 2);
    if (!f) printf("C_CRYPTO_KAT_PASS aes=1 ctr=1 sha=2 hmac=2\n");
    return f;
}
