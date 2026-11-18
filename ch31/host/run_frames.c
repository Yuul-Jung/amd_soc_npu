/* 31장 PC 시험: 틀 파일(길이 2바이트 + 틀)을 차례로 넣고 판정을 한 줄씩 찍는다. 이미지는 SHA-256, 커밋은 활성 모델 SHA-256. */
#include <stdio.h>
#include "secure_rx.h"
#include "crypto_min.h"
#include "demo_keys.h"

static void hex(const uint8_t *b, int n) { for (int i = 0; i < n; i++) printf("%02x", b[i]); }

int main(int argc, char **argv)
{
    static secure_rx_t s; static uint8_t f[2048]; uint8_t h[32]; sha256_t sh;
    FILE *fp = fopen(argv[1], "rb"); if (!fp || argc < 2) return 2;
    srx_init(&s, DEMO_K_ENC, DEMO_K_MAC, DEMO_NONCE);
    int a, b;
    while ((a = fgetc(fp)) != EOF && (b = fgetc(fp)) != EOF) {
        size_t n = (size_t)a << 8 | (size_t)b;
        if (n > sizeof f || fread(f, 1, n, fp) != n) return 3;
        sr_result_t r = srx_frame(&s, f, n);
        static const char *name[] = {"ERR_COMMIT", "ERR_MAC", "ERR_REPLAY", "ERR_FORMAT", "?", "OK_CHUNK", "OK_COMMIT", "OK_IMAGE"};
        printf("%s", name[r + 4]);
        if (r == SR_OK_COMMIT) { sha256_init(&sh); sha256_update(&sh, s.active, SF_MODEL_BYTES); sha256_final(&sh, h); printf(" "); hex(h, 8); }
        if (r == SR_OK_IMAGE) { sha256_init(&sh); sha256_update(&sh, s.image, 784); sha256_final(&sh, h); printf(" "); hex(h, 8); }
        printf("\n");
    }
    return 0;
}
