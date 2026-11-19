# 31장 AES-128·HMAC-SHA-256 모델 보호와 보안 UART (종합 4)

PC가 NPU 모델(29장 센서 모델 형식)을 **AES-128-CTR로 암호화한 뒤 HMAC-SHA-256으로 인증**(Encrypt-then-MAC)해 UART로 보내면,
MicroBlaze V가 MAC → Replay → Nonce → 복호 → 스테이징 검사 → **원자적 커밋** 순서로 받아 들이고, 이후 추론은 새 모델로 한다.
독립 AES-128·SHA-256 RTL은 NIST 알려진 정답 벡터로 따로 검증했다.

> 교육용 구현이다. 상용 보안 제품이 아니며 Basys3는 키 보호 저장소·Secure Boot·Tamper 방어를 제공하지 않는다.
> 부채널(전력·타이밍) 대책은 없다. 저장소의 키는 **TEST 키**뿐이다.

## 1. 결정 사항

| 항목 | 결정 |
|---|---|
| 역할 | AES-128(FIPS 197)·CTR(SP 800-38A) = 기밀성, HMAC-SHA-256(FIPS 198-1) = 키 기반 무결성·인증, 시퀀스 = Replay 거부. SHA-256 Digest만으로는 인증이 아니다 |
| 방식 | Encrypt-then-MAC. 태그는 `"P3SM" ‖ 헤더 전체(ver·seq·model_id·iv·len) ‖ 암호문`에 계산. **MAC 확인 전에는 복호·시퀀스 소비를 하지 않는다** |
| 키 | 암호화 16바이트·MAC 32바이트 분리. 저장소에는 결정적으로 만든 TEST 키만(`TEST_KEYS`). 보드용은 `P3_KEY_FILE`(저장소 밖)에서 `build/secure_keys.h`(저장소 제외)로. 출력은 지문 `key_fp`만, 회귀가 로그에 키 바이트가 없는지 검사 |
| Nonce | iv = nonce64 ‖ seq(BE) ‖ ctr 0. 장치가 iv의 seq를 헤더 seq와 대조 → seq가 단조 증가하는 한 같은 키에서 iv가 반복되지 않는다 |
| Replay | seq > last_seq만 수락. 인증된 메시지는 내용이 틀려도 seq를 소비(같은 메시지 재사용 차단). 인증 실패는 소비하지 않음(위조 seq로 정상 메시지를 막지 못함) |
| 커밋 | 뱅크 2개(활성·스테이징). 복호는 스테이징에만, 검사(길이·magic·차원·model_id·Bias 40비트·w ≠ -128) 통과 뒤 NPU Bias 재적재가 성공해야 활성 뱅크 전환. 실패하면 이전 모델 유지 |
| 대상 모델 | 29장 6특징→3상태 모델(blob 54바이트). 모델 A = 29장 모델(부팅 기본), 모델 B = 같은 구조·다른 seed(`train_model_b.py`) |
| 하드웨어 | 28장 Bitstream·XSA 그대로(펌웨어만). 암호 RTL은 단독 검증·OOC까지(SoC 결합은 하지 않음) |

## 2. 보안 프레임 (`'P' '3' 'M' PAYLOAD CRC16`, 정수 LE)

| 필드 | 크기 | 내용 |
|---|---|---|
| ver | 1 | 1 |
| seq | 4 | 단조 증가 |
| model_id | 4 | 평문 모델의 29장 MODEL_ID |
| iv | 16 | nonce64 ‖ seq(BE) ‖ ctr(BE) = 0 |
| len | 2 | 암호문 길이 ≤ 256 |
| ct | len | AES-128-CTR(enc_key, iv, blob) |
| tag | 32 | HMAC-SHA-256(mac_key, "P3SM" ‖ ver‖seq‖model_id‖iv‖len ‖ ct) |

응답: `SECURE result=COMMIT seq model bank last_seq` 또는 `SECURE result=REJECT reason code seq last_seq active` + `DISP`.
거부 코드: 1 VERSION, 2 LENGTH, 3 AUTH, 4 REPLAY, 5 NONCE, 6 MODEL, 7 COMMIT. 전송 오류는 `ERROR code=1 CRC / 2 TIMEOUT`(아무것도 반영하지 않음).
그 밖: `S` 추론(29장 센서 창, model_id = 활성 모델), `I` 식별(`model key_fp test_key last_seq`).
표시: FND = 활성 모델 ID 상위 16비트, LED0 = 활성 뱅크, LED13 = TEST 키, LED14 = 마지막 보안 요청 거부.

## 3. 파일

| 파일 | 내용 |
|---|---|
| `reference/secure_reference.py` | 규격 정본: 순수 Python AES-128·CTR, 프레임, 장치 기대 모델, NIST/RFC 정답, RTL 벡터, 키 헤더 |
| `reference/train_model_b.py`·`model_b_f32.json` | 모델 B(29장 학습 스크립트, seed 3131·700 epoch) |
| `rtl/p3_aes128_enc.v`·`p3_sha256_core.v`, `tb/tb_p3_aes128.sv`·`tb_p3_sha256.sv` | 암호 RTL과 시험 |
| `sw/p3_crypto.c/.h`, `host/crypto_selftest.c` | C 암호 구현과 알려진 정답 시험 |
| `sw/secure_app.c/.h`·`main.c`, `host/secure_cosim_main.c` | 보안 적재 펌웨어(29장 guard·특징 재사용), PC 빌드 main |
| `host/p3_secure_host.py` | 호스트(협동 시뮬레이션·보드, `--key-file`) |
| `scripts/run_sim.sh`·`run_synth.sh`·`build_sw.sh` | PC 검증, 암호 RTL OOC, ELF |
| `part03/common/sw/p3_stack_4k.c`·`elf_mem_check.sh` | 28~31장 보드 ELF 스택 4 KB와 메모리 배치 검사(이 장에서 발견·추가) |

## 4. 결과 (실제 실행)

| 항목 | 결과 |
|---|---|
| 기준·C 암호 알려진 정답 | `SECURE_REFERENCE_SELFTEST_PASS`(AES 2, CTR 1, SHA 2, HMAC 2, `cryptography` 교차 50), `C_CRYPTO_KAT_PASS` |
| AES-128 RTL | 204블록(KAT 6) PASS, 11클록/블록 (`validation/rtl_sim.log`) |
| SHA-256 RTL | 50메시지 136블록 PASS, 66클록/블록 |
| 암호 RTL 변이 6종 | **6/6 검출** |
| 종단간 협동 시뮬레이션 | 35/35 검사 PASS(모델 B 적재·추론, 거부 시나리오, A 재적재), 로그 키 노출 검사 `KEY_NOT_IN_LOGS_PASS` (`validation/rtl_cosim.csv`) |
| 펌웨어 변이 7종 | MAC 생략, Replay, nonce 바인딩, 인증 실패 시 seq 소비, 헤더·blob ID, 길이 한계 → **7/7 검출** |
| 암호 RTL OOC 배선 | AES: LUT 554, FF 270, BRAM 5, WNS +1.829 ns / SHA-256: LUT 1,394, FF 1,044, **WNS +0.117 ns** @100 MHz (`validation/synth_ooc_summary.md`) |
| Vitis ELF | 28장 XSA·Bitstream 그대로, `secure_app.elf` 61,264 B, SHA-256 f62f051390c36c82, 스택 끝 61,272 ≤ 65,536, `ELF_MEM_PASS` (`validation/build_sw.log`) |
| **Basys3 실물** | **NOT_RUN** — `ch27/docs/BOARD_CHECKLIST.md` B25~B26, 사용자와 함께 |

> **SHA-256 타이밍 주의:** 100 MHz 배선 여유가 +0.117 ns뿐이다. 배치·배선 결과는 실행마다 달라질 수 있으므로 **빌드할 때마다 `run_synth.sh` 결과의 WNS를 다시 확인한다.** 음수가 나오면 라운드 덧셈을 파이프라인으로 나눈다.

## 5. 알려진 한계

- **재부팅 뒤 Replay:** last_seq는 RAM에만 있어 Reset 뒤 0이 된다. 전에 받은 정상 프레임을 재부팅 뒤 다시 보내면 수락된다. 막으려면 비휘발 저장(QSPI 플래시의 단조 카운터) 또는 장치 난수 기반 세션 challenge가 필요하다(Basys3에 TRNG 없음).
- **키 저장:** 키가 ELF·BRAM 초기값(Bitstream)에 평문으로 들어간다. 보드를 가진 사람은 읽을 수 있다. Bitstream 암호화(eFUSE/BBRAM)는 이 장 범위 밖이다.
- **일정시간 비교:** `ct_equal`은 끝까지 비교하지만, 기능 시험으로는 시간 특성을 확인할 수 없다(코드 검토 항목). 컴파일러 최적화 수준에 따라 달라질 수 있다.
- **암호 RTL:** 단독 검증·OOC만 했다. SoC에 넣어 펌웨어가 쓰게 하려면 AXI 래퍼와 별도 검증이 필요하다. SHA-256 코어는 100 MHz 배선 여유가 +0.117 ns로 작다(K 표 + 덧셈 체인 15단).
- 카운터는 하위 32비트에서 감싼다. 모델 blob(54바이트, 4블록)에서는 문제가 없지만 큰 데이터에는 블록 수 제한을 둬야 한다.
