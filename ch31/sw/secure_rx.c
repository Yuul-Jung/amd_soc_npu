/* 31장 인증 틀 수신 구현 */
#include "secure_rx.h"
#include "crypto_min.h"

void srx_init(secure_rx_t *s, const uint8_t *k_enc, const uint8_t *k_mac, const uint8_t *nonce)
{
    s->k_enc = k_enc; s->k_mac = k_mac; s->nonce = nonce; s->last_ctr = 0; s->commits = 0;
    for (size_t i = 0; i < SF_MODEL_BYTES; i++) { s->staging[i] = 0; s->active[i] = 0; }
    for (size_t i = 0; i < sizeof s->got; i++) s->got[i] = 0;
}

sr_result_t srx_frame(secure_rx_t *s, const uint8_t *f, size_t n)
{
    static uint8_t plain[1024];
    uint8_t tag[32], iv[16];
    if (n < 8 + 16 || f[0] != 'S') return SR_ERR_FORMAT;
    uint32_t ctr = (uint32_t)f[2] << 24 | (uint32_t)f[3] << 16 | (uint32_t)f[4] << 8 | f[5];
    size_t len = (size_t)f[6] << 8 | f[7];
    if (len > sizeof plain || n != 8 + len + 16) return SR_ERR_FORMAT;
    if (ctr <= s->last_ctr) return SR_ERR_REPLAY;                 /* 재전송·되감기 */
    hmac_sha256(s->k_mac, 16, f, 8 + len, tag);
    if (!ct_equal(tag, f + 8 + len, 16)) return SR_ERR_MAC;       /* 변조·다른 키 */
    s->last_ctr = ctr;                                             /* 인증된 틀만 카운터를 올린다 */
    for (int i = 0; i < 8; i++) iv[i] = s->nonce[i];
    for (int i = 0; i < 4; i++) { iv[8 + i] = f[2 + i]; iv[12 + i] = 0; }
    aes128_ctr(s->k_enc, iv, f + 8, plain, len);
    switch (f[1]) {
    case SF_MODEL_CHUNK: {                                         /* 오프셋 2바이트 + 데이터 */
        size_t off = (size_t)plain[0] << 8 | plain[1];
        if (len < 2 || off + len - 2 > SF_MODEL_BYTES) return SR_ERR_FORMAT;
        for (size_t i = 0; i < len - 2; i++) { s->staging[off + i] = plain[2 + i]; s->got[(off + i) / 8] |= (uint8_t)(1u << ((off + i) % 8)); }
        return SR_OK_CHUNK;
    }
    case SF_MODEL_COMMIT: {                                        /* 전체 모델 SHA-256 32바이트 */
        uint8_t h[32]; sha256_t sh;
        if (len != 32) return SR_ERR_FORMAT;
        for (size_t i = 0; i < SF_MODEL_BYTES; i++) if (!(s->got[i / 8] >> (i % 8) & 1)) return SR_ERR_COMMIT;
        sha256_init(&sh); sha256_update(&sh, s->staging, SF_MODEL_BYTES); sha256_final(&sh, h);
        if (!ct_equal(h, plain, 32)) return SR_ERR_COMMIT;          /* 활성 모델은 그대로 */
        for (size_t i = 0; i < SF_MODEL_BYTES; i++) s->active[i] = s->staging[i];
        s->commits++;
        return SR_OK_COMMIT;
    }
    case SF_IMAGE:
        if (len != 784) return SR_ERR_FORMAT;
        for (size_t i = 0; i < 784; i++) s->image[i] = plain[i];
        return SR_OK_IMAGE;
    default:
        return SR_ERR_FORMAT;
    }
}
