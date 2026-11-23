/* 교육용 암호 구현. S-box 표는 reference/secure_reference.py(SBOX 계산)에서 생성했다.
 * 정답 확인: NIST FIPS 197·SP 800-38A·FIPS 180-4 예제, RFC 4231 HMAC — host/crypto_selftest.c와 PC 시뮬레이션.
 */
#include "p3_crypto.h"

static const uint8_t sbox[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
};

static uint8_t xtime(uint8_t a) { return (uint8_t)((a << 1) ^ ((a & 0x80u) ? 0x1Bu : 0u)); }

void aes128_encrypt_block(const uint8_t key[16], const uint8_t in[16], uint8_t out[16])
{
    uint8_t rk[16], s[16], t[16], tmp[4], rcon = 1, a0, a1, a2, a3, x;
    int r, i, c;
    for (i = 0; i < 16; i++) {
        rk[i] = key[i];
        s[i] = in[i] ^ key[i];
    }
    for (r = 1; r <= 10; r++) {
        tmp[0] = (uint8_t)(sbox[rk[13]] ^ rcon); tmp[1] = sbox[rk[14]]; tmp[2] = sbox[rk[15]]; tmp[3] = sbox[rk[12]];
        for (i = 0; i < 16; i++)                       /* 다음 라운드 키(즉석 생성) */
            rk[i] ^= (i < 4) ? tmp[i] : rk[i - 4];
        rcon = xtime(rcon);
        for (i = 0; i < 16; i++)                       /* SubBytes + ShiftRows */
            t[i] = sbox[s[(i + 4 * (i % 4)) % 16]];
        for (c = 0; c < 4; c++) {
            a0 = t[4 * c]; a1 = t[4 * c + 1]; a2 = t[4 * c + 2]; a3 = t[4 * c + 3];
            if (r != 10) {                             /* MixColumns */
                x = a0 ^ a1 ^ a2 ^ a3;
                t[4 * c]     = a0 ^ x ^ xtime(a0 ^ a1);
                t[4 * c + 1] = a1 ^ x ^ xtime(a1 ^ a2);
                t[4 * c + 2] = a2 ^ x ^ xtime(a2 ^ a3);
                t[4 * c + 3] = a3 ^ x ^ xtime(a3 ^ a0);
            }
        }
        for (i = 0; i < 16; i++)
            s[i] = t[i] ^ rk[i];
    }
    for (i = 0; i < 16; i++)
        out[i] = s[i];
}

void aes128_ctr(const uint8_t key[16], const uint8_t iv[16], const uint8_t *in, uint8_t *out, uint32_t n)
{
    uint8_t cb[16], ks[16];
    uint32_t i, k, ctr = ((uint32_t)iv[12] << 24) | ((uint32_t)iv[13] << 16) | ((uint32_t)iv[14] << 8) | iv[15];
    for (i = 0; i < 12; i++)
        cb[i] = iv[i];
    for (i = 0; i < n; i += 16) {
        cb[12] = (uint8_t)(ctr >> 24); cb[13] = (uint8_t)(ctr >> 16); cb[14] = (uint8_t)(ctr >> 8); cb[15] = (uint8_t)ctr;
        aes128_encrypt_block(key, cb, ks);
        for (k = 0; k < 16 && i + k < n; k++)
            out[i + k] = in[i + k] ^ ks[k];
        ctr++;
    }
}

static const uint32_t K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};

#define ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void sha256_block(uint32_t h[8], const uint8_t *p)
{
    uint32_t w[64], a, b, c, d, e, f, g, hh, t1, t2;
    int i;
    for (i = 0; i < 16; i++)
        w[i] = ((uint32_t)p[4 * i] << 24) | ((uint32_t)p[4 * i + 1] << 16) | ((uint32_t)p[4 * i + 2] << 8) | p[4 * i + 3];
    for (i = 16; i < 64; i++)
        w[i] = (ROR(w[i - 2], 17) ^ ROR(w[i - 2], 19) ^ (w[i - 2] >> 10)) + w[i - 7]
               + (ROR(w[i - 15], 7) ^ ROR(w[i - 15], 18) ^ (w[i - 15] >> 3)) + w[i - 16];
    a = h[0]; b = h[1]; c = h[2]; d = h[3]; e = h[4]; f = h[5]; g = h[6]; hh = h[7];
    for (i = 0; i < 64; i++) {
        t1 = hh + (ROR(e, 6) ^ ROR(e, 11) ^ ROR(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
        t2 = (ROR(a, 2) ^ ROR(a, 13) ^ ROR(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

void sha256_init(sha256_t *s)
{
    static const uint32_t iv[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    int i;
    for (i = 0; i < 8; i++)
        s->h[i] = iv[i];
    s->len = 0;
    s->fill = 0;
}

void sha256_update(sha256_t *s, const uint8_t *p, uint32_t n)
{
    uint32_t i;
    for (i = 0; i < n; i++) {
        s->buf[s->fill++] = p[i];
        if (s->fill == 64) {
            sha256_block(s->h, s->buf);
            s->fill = 0;
        }
    }
    s->len += n;
}

void sha256_final(sha256_t *s, uint8_t out[32])
{
    uint64_t bits = s->len * 8u;
    uint8_t pad = 0x80, z = 0, lb[8];
    int i;
    sha256_update(s, &pad, 1);
    while (s->fill != 56)
        sha256_update(s, &z, 1);
    for (i = 0; i < 8; i++)
        lb[i] = (uint8_t)(bits >> (56 - 8 * i));
    sha256_update(s, lb, 8);
    for (i = 0; i < 32; i++)
        out[i] = (uint8_t)(s->h[i / 4] >> (24 - 8 * (i % 4)));
}

void hmac_sha256(const uint8_t *key, uint32_t klen, const uint8_t *a, uint32_t na, const uint8_t *b, uint32_t nb,
                 uint8_t out[32])
{
    uint8_t k0[64], inner[32];
    sha256_t s;
    uint32_t i;
    for (i = 0; i < 64; i++)
        k0[i] = (uint8_t)((i < klen ? key[i] : 0) ^ 0x36);
    sha256_init(&s);
    sha256_update(&s, k0, 64);
    sha256_update(&s, a, na);
    sha256_update(&s, b, nb);
    sha256_final(&s, inner);
    for (i = 0; i < 64; i++)
        k0[i] ^= 0x36 ^ 0x5C;
    sha256_init(&s);
    sha256_update(&s, k0, 64);
    sha256_update(&s, inner, 32);
    sha256_final(&s, out);
}

int ct_equal(const uint8_t *a, const uint8_t *b, uint32_t n)
{
    uint32_t i;
    uint8_t d = 0;
    for (i = 0; i < n; i++)
        d |= a[i] ^ b[i];
    return d == 0;
}
