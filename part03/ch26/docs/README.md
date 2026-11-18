# 제26장 · 3×3 소형 CNN 합성곱 (선택 실습)

## 1. 구조

```text
픽셀 스트림(8×8, signed INT8, valid/last, 버블 허용)
  │
  ├─ 라인 버퍼 lb1(행 r−1)·lb2(행 r−2), 각 8칸
  └─ 3×3 창 레지스터 win[0..8] ← (lb2[c], lb1[c], pix) 열을 오른쪽에서 밀어 넣음
        │ r ≥ 2 && c ≥ 2 → 창 유효, 출력 위치 (r−2, c−2)
        ▼
  02장 dsp_multiplier × 9 (등록 곱)  →  3항 부분합 × 3  →  부분합 3 + Bias  →  ReLU(선택)  →  out (signed 25비트)
```

| 항목 | 계약 |
|---|---|
| 신규 RTL | `rtl/p3_conv3x3_8x8.v` |
| 재사용 | 02장 `dsp_multiplier` 9개, host_tools `dot_signed`(기준모델), 19장 `synth_ooc.tcl` |
| 연산 | Cross-Correlation(커널 뒤집지 않음), stride 1, padding 0, 1채널 → 1채널, 출력 6×6 = 36픽셀, 필터당 324 MAC |
| 형식 | 입력·커널 signed INT8, Bias signed 24비트, 출력 signed 25비트(\|9·128·128\| + 2²³ < 2²⁴) |
| 지연·처리량 | 픽셀 수락 → 출력 **5클록**(창·곱·부분합·합·ReLU 레지스터), 1픽셀/클록, 프레임 붙여 보내기 가능 |
| 커널·Bias 쓰기 | `load_ready_o`(프레임 시작 전, 파이프라인 비었음)일 때만. 그 밖·주소 ≥ 9 → `error_o`, 무시 |
| 프레임 오류 | 이른 last → 오류 후 새 프레임. 64번째에 last 없음 → 오류 후 다음 last까지 버림(13장 규칙). 이미 나간 출력은 취소하지 않음 |
| Reset | 동기 Active-Low. 위치·파이프라인·커널·Bias 초기화(라인 버퍼 데이터는 유지, 창 유효 전에는 쓰이지 않음) |

## 2. 실행

```bash
bash part03/ch26/scripts/run_sim.sh                                            # RTL·Python 비교
VIVADO_SETTINGS=<Vivado>/settings64.sh bash part03/ch26/scripts/run_synth.sh   # OOC 합성·배선
```

기대 출력:

```text
PYTHON_CONV_SELF_TEST_PASS frames=26 out=6x6 macs_per_frame=324 first_spec=-6 seed=2626
RTL_SIM_PASS CONV3X3 frames=26 outputs_per_frame=36 latency=5 errors_checked=4
PYTHON_RTL_COMPARE_PASS frames=26 outputs=936 bit_exact=1
SYNTH_OOC_SUMMARY configs=1 wns_negative=0 routed=1 route_wns_negative=0 out=synth_ooc_summary.md
```

## 3. 검증 결과

- 26장 규격 예제(`img = r·8+c`, 커널 `[[1,0,−1]]×3`) 첫 출력 **−6**, ReLU 버전, 창 위치 판별 9개(one-hot 커널), 누산·Bias 극값, 전부 음수 → ReLU 0, 무작위 12개 — 26프레임 936출력 비트 단위 일치
- 상시 검사: 출력 위치 행 우선 순서, `out_last` = 36번째, 지연 5클록 일정, LFSR 버블·버블 없는 연속 프레임
- 오류: 짧은 프레임, 긴 프레임(재동기), 커널 주소 9, 프레임 중 커널 쓰기(오류 + 커널 불변 확인), 프레임 중 Reset 후 정상
- 변이 시험 10종 검출: 창 상단 행 탭, 라인 버퍼 이동, 창 유효 조건, Bias 누락, ReLU 무시, 긴 프레임 버리기, 프레임 중 커널 쓰기 허용, 창 중간 행 탭, 부분합 항, 단계 태그 어긋남
- **Vivado 2024.2 OOC 배선 후 @100 MHz:** DSP48E1 9, LUT 145, FF 196, BRAM 0, **WNS +4.647 ns**

### 설계 중 실제로 고친 점

1. 처음에는 9개 곱 + Bias를 한 클록에 더했다 → 합성이 덧셈을 DSP 캐스케이드로 묶어 **WNS −8.089 ns**(경로 17.5 ns). 덧셈 트리를 두 단으로 나눠 지연 3 → 5클록.
2. 나눈 뒤에도 부분합이 DSP 캐스케이드로 묶여 OOC 배치에서 **PCOUT 48핀 배선 실패**. 부분합·합 레지스터에 `use_dsp = "no"`를 두어 LUT 캐리 체인으로 — DSP는 곱 9개만 사용.

**범위 경계:** 8×8·1채널 합성곱 데이터 경로다. 28×28 CNN 전체, 다채널, Pooling, MNIST 정확도, 객체검출이 아니다. NPU·SoC에는 연결하지 않았다(27장 최종 통합 필수 의존성 아님). 실물 미실행.
