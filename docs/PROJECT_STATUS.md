# 장 프로젝트 검증 현황 (자동 생성)

`python3 tools/guide/build_projects.py`가 `pNN/project.json`과 `validation/` 증거로 만든다. 직접 수정하지 않는다.
장 페이지(학습안내서)에는 검증 상태를 싣지 않고 여기에 모은다.

✅ 통과 · ❌ 실패 · ⏳ 실행 대기/미검증/미실시 · — 해당 없음

## 1장 · UART 계산기 ([p01_uart_calc_v01.html](../p01_uart_calc_v01.html))

| 구분 | 게이트 | 상태 | 근거 |
|---|---|---|---|
| 장 전체 | HTML_PASS | ✅ | v01 · 생성기 |
| 장 전체 | HOST_MODEL_PASS | ✅ | PYTHON_P01_SELF_TEST_PASS |
| 장 전체 | RTL_SIM_PASS | ✅ | 장 Top STAGE 1~4 · Icarus Verilog 12.0 · 2026-11-23 |
| 장 전체 | SYNTH_TIMING_PASS | ✅ | STAGE 1~4 비트스트림 · 2026-11-23 |
| 장 전체 | XSIM_RTL_PASS | ✅ | Vivado Simulator v2024.2.0 · Icarus와 같은 TB·판정 줄 · 2026-11-23 · p01/validation/xsim_rtl_20261123.log |
| 장 전체 | BOARD_PASS | ⏳ | ⚠ 미실시 · 실물 보드 확인 대기 |
| 1-1 UART 에코 | HOST_MODEL_PASS | — | 해당 없음 (Python 기준 모델 없음) |
| 1-1 UART 에코 | RTL_SIM_PASS | ✅ | UART_ECHO_RTL_SIM_PASS decoded=2 · Icarus Verilog 12.0 · 2026-11-18 |
| 1-1 UART 에코 | SYNTH_TIMING_PASS | ✅ | ch00 basys3_uart_echo_top WNS=4.696 WHS=0.038 LUT=196 FF=128 DSP48E1=0… · 2026-11-20 |
| 1-1 UART 에코 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 1-1 UART 에코 | 장 Top STAGE=1 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 1-1 UART 에코 | 장 Top STAGE=1 합성·타이밍 | ✅ | 통과 · WNS=4.814 WHS=0.057 DRC_ERRORS=0 LUT=238 FF=177 DSP48E1=0 |
| 1-2 MAC 누산 | HOST_MODEL_PASS | ✅ | PYTHON_SELF_TEST_PASS configurations=INT8/32,INT16/40 |
| 1-2 MAC 누산 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS INT16/40 cycles=35304 외 1건 · Icarus Verilog 12.0 · 2026-11-18 |
| 1-2 MAC 누산 | SYNTH_TIMING_PASS | ✅ | 장 Top STAGE 2 배선 후 WNS 3.339 ns · WHS 0.035 ns (구 장 단독 OOC 판정 없음) · 2026-11-23 |
| 1-2 MAC 누산 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 1-2 MAC 누산 | 장 Top STAGE=2 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 1-2 MAC 누산 | 장 Top STAGE=2 합성·타이밍 | ✅ | 통과 · WNS=3.339 WHS=0.035 DRC_ERRORS=0 LUT=379 FF=285 DSP48E1=1 |
| 1-3 DSP48E1 곱셈 | HOST_MODEL_PASS | ✅ | PYTHON_PRODUCT_SELF_TEST_PASS INT16,INT8,native25x18 |
| 1-3 DSP48E1 곱셈 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS A=16 B=16 ACC=40 cycles=37360 외 2건 · Icarus Verilog 12.0 · 2026-11-18 |
| 1-3 DSP48E1 곱셈 | SYNTH_TIMING_PASS | ✅ | 장 Top STAGE 3 배선 후 WNS 3.569 ns · WHS 0.036 ns (구 장 단독 OOC 판정 없음) · 2026-11-23 |
| 1-3 DSP48E1 곱셈 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 1-3 DSP48E1 곱셈 | 장 Top STAGE=3 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 1-3 DSP48E1 곱셈 | 장 Top STAGE=3 합성·타이밍 | ✅ | 통과 · WNS=3.569 WHS=0.036 DRC_ERRORS=0 LUT=425 FF=290 DSP48E1=2 |
| 1-4 MAC 파이프라인 | HOST_MODEL_PASS | ✅ | PYTHON_PIPELINE_SELF_TEST_PASS ACC=32,40 |
| 1-4 MAC 파이프라인 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS INT16/40 cycles=2546 외 1건 · Icarus Verilog 12.0 · 2026-11-18 |
| 1-4 MAC 파이프라인 | SYNTH_TIMING_PASS | ✅ | ch03 mac_pipeline_core WNS=8.270 WHS=0.251 LUT=3 FF=2 DSP48E1=1 RAMB=0 · 2026-11-20 |
| 1-4 MAC 파이프라인 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 1-4 MAC 파이프라인 | 장 Top STAGE=4 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 1-4 MAC 파이프라인 | 장 Top STAGE=4 합성·타이밍 | ✅ | 통과 · WNS=3.830 WHS=0.060 DRC_ERRORS=0 LUT=428 FF=290 DSP48E1=3 |

## 2장 · 4뉴런 NPU 보드 ([p02_npu4_board_v01.html](../p02_npu4_board_v01.html))

| 구분 | 게이트 | 상태 | 근거 |
|---|---|---|---|
| 장 전체 | HTML_PASS | ✅ | v01 · 생성기 |
| 장 전체 | HOST_MODEL_PASS | ✅ | PYTHON_P02_SELF_TEST_PASS |
| 장 전체 | RTL_SIM_PASS | ✅ | 장 Top STAGE 1~8 · Icarus Verilog 12.0 · 2026-11-23 |
| 장 전체 | SYNTH_TIMING_PASS | ✅ | STAGE 1~8 비트스트림 · 2026-11-23 |
| 장 전체 | XSIM_RTL_PASS | ✅ | Vivado Simulator v2024.2.0 · Icarus와 같은 TB·판정 줄 · 2026-11-23 · p02/validation/xsim_rtl_20261123.log |
| 장 전체 | BOARD_PASS | ⏳ | ⚠ 미실시 · 실물 보드 확인 대기 |
| 2-1 BRAM 동기 버퍼 | HOST_MODEL_PASS | ✅ | PYTHON_SELF_TEST_PASS reset_retention,collision,uninitialized |
| 2-1 BRAM 동기 버퍼 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS BRAM W=16 A=8 cycles=1016 외 1건 · 도구 버전 미기록 · 2026-11-18 |
| 2-1 BRAM 동기 버퍼 | SYNTH_TIMING_PASS | ✅ | 장 Top STAGE 1 배선 후 WNS 3.272 ns · WHS 0.083 ns (구 장 단독 OOC 판정 없음) · 2026-11-23 |
| 2-1 BRAM 동기 버퍼 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 2-1 BRAM 동기 버퍼 | 장 Top STAGE=1 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 2-1 BRAM 동기 버퍼 | 장 Top STAGE=1 합성·타이밍 | ✅ | 통과 · WNS=3.272 WHS=0.083 DRC_ERRORS=0 LUT=576 FF=395 DSP48E1=0 RAMB18=5 |
| 2-2 고정소수점 양자화 | HOST_MODEL_PASS | ✅ | PYTHON_FIXED_SELF_TEST_PASS |
| 2-2 고정소수점 양자화 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS FIXED IW=32 OW=8 SHIFT=8 cycles=2035 외 2건 · 도구 버전 미기록 · 2026-11-18 |
| 2-2 고정소수점 양자화 | SYNTH_TIMING_PASS | ✅ | ch05 fixed_quantizer WNS=8.872 WHS=0.230 LUT=164 FF=10 DSP48E1=0 RAMB=… · 2026-11-20 |
| 2-2 고정소수점 양자화 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 2-2 고정소수점 양자화 | 장 Top STAGE=2 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 2-2 고정소수점 양자화 | 장 Top STAGE=2 합성·타이밍 | ✅ | 통과 · WNS=1.136 WHS=0.056 DRC_ERRORS=0 LUT=757 FF=441 DSP48E1=0 RAMB18=5 |
| 2-3 벡터 내적 | HOST_MODEL_PASS | ✅ | PYTHON_DOT_SELF_TEST_PASS cases=78 INT16/40 seed=307 |
| 2-3 벡터 내적 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS DOT INT16/40 cases=78 외 1건 · 도구 버전 미기록 · 2026-11-18 |
| 2-3 벡터 내적 | SYNTH_TIMING_PASS | ✅ | ch07 vector_dot_core WNS=5.418 WHS=0.223 LUT=39 FF=62 DSP48E1=1 RAMB=0 · 2026-11-20 |
| 2-3 벡터 내적 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 2-3 벡터 내적 | 장 Top STAGE=3 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 2-3 벡터 내적 | 장 Top STAGE=3 합성·타이밍 | ✅ | 통과 · WNS=0.628 WHS=0.024 DRC_ERRORS=0 LUT=956 FF=567 DSP48E1=1 RAMB18=5 |
| 2-4 4PE 병렬 어레이 | HOST_MODEL_PASS | ✅ | PYTHON_PE_SELF_TEST_PASS INT16/40 cases=26 seed=308 |
| 2-4 4PE 병렬 어레이 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS PE4 INT16/40 cases=26 외 1건 · 도구 버전 미기록 · 2026-11-18 |
| 2-4 4PE 병렬 어레이 | SYNTH_TIMING_PASS | ✅ | ch08 pe_array4 WNS=3.937 WHS=0.146 LUT=267 FF=453 DSP48E1=4 RAMB=0 · 2026-11-20 |
| 2-4 4PE 병렬 어레이 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 2-4 4PE 병렬 어레이 | 장 Top STAGE=4 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 2-4 4PE 병렬 어레이 | 장 Top STAGE=4 합성·타이밍 | ✅ | 통과 · WNS=1.642 WHS=0.022 DRC_ERRORS=0 LUT=1427 FF=1261 DSP48E1=5 RAMB18=5 |
| 2-5 Dense 4뉴런 레이어 | HOST_MODEL_PASS | ✅ | PYTHON_DENSE_SELF_TEST_PASS INT16/40 cases=46 seed=309 |
| 2-5 Dense 4뉴런 레이어 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS DENSE4 INT16/40 cases=46 외 1건 · 도구 버전 미기록 · 2026-11-18 |
| 2-5 Dense 4뉴런 레이어 | SYNTH_TIMING_PASS | ✅ | ch09 dense_layer4 WNS=1.339 WHS=0.123 LUT=486 FF=710 DSP48E1=4 RAMB=0 · 2026-11-20 |
| 2-5 Dense 4뉴런 레이어 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 2-5 Dense 4뉴런 레이어 | 장 Top STAGE=5 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 2-5 Dense 4뉴런 레이어 | 장 Top STAGE=5 합성·타이밍 | ✅ | 통과 · WNS=1.381 WHS=0.024 DRC_ERRORS=0 LUT=2084 FF=2182 DSP48E1=9 RAMB18=5 |
| 2-6 4뉴런 NPU Core | HOST_MODEL_PASS | ✅ | PYTHON_NPU_SELF_TEST_PASS INT16/40 datasets=22 inferences=44 seed=310 |
| 2-6 4뉴런 NPU Core | RTL_SIM_PASS | ✅ | RTL_SIM_PASS NPU INT16/40 datasets=22 inferences=44 외 1건 · 도구 버전 미기록 · 2026-11-18 |
| 2-6 4뉴런 NPU Core | SYNTH_TIMING_PASS | ✅ | ch10 npu_core WNS=1.130 WHS=0.117 LUT=529 FF=963 DSP48E1=4 RAMB=5 · 2026-11-20 |
| 2-6 4뉴런 NPU Core | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 2-6 4뉴런 NPU Core | 장 Top STAGE=6 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 2-6 4뉴런 NPU Core | 장 Top STAGE=6 합성·타이밍 | ✅ | 통과 · WNS=0.560 WHS=0.019 DRC_ERRORS=0 LUT=2619 FF=3138 DSP48E1=13 RAMB18=10 |
| 2-7 UART 모델 적재 | HOST_MODEL_PASS | ✅ | PC_GOLDEN_COMPARE_PASS predictions=6 model_edit=1 |
| 2-7 UART 모델 적재 | RTL_SIM_PASS | ✅ | INTEGRATED_UART_RTL_SIM_PASS classes=6 model_edit=1 invalid_… · Icarus Verilog 12.0 · 2026-11-18 |
| 2-7 UART 모델 적재 | SYNTH_TIMING_PASS | ✅ | ch12 basys3_npu_top WNS=1.993 WHS=0.024 DRC_ERRORS=0 LUT=1657 FF=1262 … (12장 통합 Top) · 2026-11-23 |
| 2-7 UART 모델 적재 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 2-7 UART 모델 적재 | 장 Top STAGE=7 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 2-7 UART 모델 적재 | 장 Top STAGE=7 합성·타이밍 | ✅ | 통과 · WNS=0.875 WHS=0.012 DRC_ERRORS=0 LUT=3037 FF=3431 DSP48E1=13 RAMB18=10 |
| 2-8 통합 NPU Top | HOST_MODEL_PASS | ✅ | PC_GOLDEN_COMPARE_PASS predictions=6 model_edit=1 (11장 증거) |
| 2-8 통합 NPU Top | RTL_SIM_PASS | ✅ | 회귀 결과 표 13단계 모두 RTL_SIM_PASS · Icarus Verilog 12.0 · 2026-11-19 |
| 2-8 통합 NPU Top | SYNTH_TIMING_PASS | ✅ | ch12 basys3_npu_top WNS=1.993 WHS=0.024 DRC_ERRORS=0 LUT=1657 FF=1262 … · 2026-11-23 |
| 2-8 통합 NPU Top | TIMING_SIM_PASS | ✅ | TIMING_SIM_PASS ch12 basys3_npu_top post-route SDF(slow) classes=6 mod… · 2026-11-23 |
| 2-8 통합 NPU Top | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 2-8 통합 NPU Top | 장 Top STAGE=8 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 2-8 통합 NPU Top | 장 Top STAGE=8 합성·타이밍 | ✅ | 통과 · WNS=0.642 WHS=0.019 DRC_ERRORS=0 LUT=4351 FF=4395 DSP48E1=17 RAMB18=15 |

## 3장 · 8×8 MNIST (CPU 없음) ([p03_mnist8x8_v01.html](../p03_mnist8x8_v01.html))

| 구분 | 게이트 | 상태 | 근거 |
|---|---|---|---|
| 장 전체 | HTML_PASS | ✅ | v01 · 생성기 |
| 장 전체 | HOST_MODEL_PASS | ✅ | PYTHON_P03_SELF_TEST_PASS |
| 장 전체 | RTL_SIM_PASS | ✅ | 장 Top STAGE 1~4 · Icarus Verilog 12.0 · 2026-11-23 |
| 장 전체 | SYNTH_TIMING_PASS | ✅ | STAGE 1~4 비트스트림 · 2026-11-23 |
| 장 전체 | XSIM_RTL_PASS | ✅ | Vivado Simulator v2024.2.0 · Icarus와 같은 TB·판정 줄 · 2026-11-23 · p03/validation/xsim_rtl_20261123.log |
| 장 전체 | BOARD_PASS | ⏳ | ⚠ 미실시 · 실물 보드 확인 대기 |
| 3-1 8×8 입력 프레임 | HOST_MODEL_PASS | ✅ | PYTHON_FRAME64_SELF_TEST_PASS items=2664 frames=36 short=2 long=3 seed=1313 |
| 3-1 8×8 입력 프레임 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS FRAME64 frames=36 short=2 long=3 · Vivado Simulator 2024.2.0 · 날짜 미기록 |
| 3-1 8×8 입력 프레임 | SYNTH_TIMING_PASS | ✅ | 장 Top STAGE 1 배선 후 WNS 2.863 ns · WHS 0.042 ns (구 장 단독 OOC 판정 없음) · 2026-11-23 |
| 3-1 8×8 입력 프레임 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 3-1 8×8 입력 프레임 | 장 Top STAGE=1 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 3-1 8×8 입력 프레임 | 장 Top STAGE=1 합성·타이밍 | ✅ | 통과 · WNS=2.863 WHS=0.042 DRC_ERRORS=0 LUT=504 FF=317 DSP48E1=0 RAMB18=0 |
| 3-2 4PE 3그룹 10분류 코어 | HOST_MODEL_PASS | ✅ | PYTHON_GROUP10_SELF_TEST_PASS cases=41 groups=4+4+2 seed=1414 |
| 3-2 4PE 3그룹 10분류 코어 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS GROUP10 cases=41 start_to_done_cycles=206 error… · Vivado Simulator 2024.2.0 · 날짜 미기록 |
| 3-2 4PE 3그룹 10분류 코어 | SYNTH_TIMING_PASS | ✅ | 장 Top STAGE 2 배선 후 WNS 1.084 ns · WHS 0.014 ns (구 장 단독 OOC 판정 없음) · 2026-11-23 |
| 3-2 4PE 3그룹 10분류 코어 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 3-2 4PE 3그룹 10분류 코어 | 장 Top STAGE=2 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 3-2 4PE 3그룹 10분류 코어 | 장 Top STAGE=2 합성·타이밍 | ✅ | 통과 · WNS=1.084 WHS=0.014 DRC_ERRORS=0 LUT=1704 FF=1752 DSP48E1=4 RAMB18=4 |
| 3-3 64→10·64→8·8→10 Dense | HOST_MODEL_PASS | ✅ | PYTHON_DENSE_SELF_TEST_PASS shape=64x10 ops=5238 frames=20 |
| 3-3 64→10·64→8·8→10 Dense | RTL_SIM_PASS | ✅ | RTL_SIM_PASS DENSE 64x10 frames=20 w_writes=5127 b_writes=91… 외 2건 · Vivado Simulator 2024.2.0 · 날짜 미기록 |
| 3-3 64→10·64→8·8→10 Dense | SYNTH_TIMING_PASS | ✅ | 장 Top STAGE 3 배선 후 WNS 0.755 ns · WHS 0.036 ns (구 장 단독 OOC 판정 없음) · 2026-11-23 |
| 3-3 64→10·64→8·8→10 Dense | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 3-3 64→10·64→8·8→10 Dense | 장 Top STAGE=3 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 3-3 64→10·64→8·8→10 Dense | 장 Top STAGE=3 합성·타이밍 | ✅ | 통과 · WNS=0.755 WHS=0.036 DRC_ERRORS=0 LUT=2797 FF=2849 DSP48E1=12 RAMB18=12 |
| 3-4 MLP 64→8→10 | HOST_MODEL_PASS | ✅ | PYTHON_MLP_SELF_TEST_PASS ops=4933 frames=27 seed=1616 |
| 3-4 MLP 64→8→10 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS MLP64_8_10 frames=27 start_to_done_cycles=180 e… · Vivado Simulator 2024.2.0 · 날짜 미기록 |
| 3-4 MLP 64→8→10 | SYNTH_TIMING_PASS | ✅ | 장 Top STAGE 4 배선 후 WNS 0.547 ns · WHS 0.032 ns (구 장 단독 OOC 판정 없음) · 2026-11-23 |
| 3-4 MLP 64→8→10 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 3-4 MLP 64→8→10 | 장 Top STAGE=4 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 3-4 MLP 64→8→10 | 장 Top STAGE=4 합성·타이밍 | ✅ | 통과 · WNS=0.547 WHS=0.032 DRC_ERRORS=0 LUT=4332 FF=4014 DSP48E1=20 RAMB18=20 |

## 4장 · 784 가속기 설계 공간 ([p04_tile784_v01.html](../p04_tile784_v01.html))

| 구분 | 게이트 | 상태 | 근거 |
|---|---|---|---|
| 장 전체 | HTML_PASS | ✅ | v01 · 생성기 |
| 장 전체 | HOST_MODEL_PASS | ✅ | PYTHON_P04_SELF_TEST_PASS |
| 장 전체 | RTL_SIM_PASS | ✅ | 장 Top STAGE 1~4 · Icarus Verilog 12.0 · 2026-11-23 |
| 장 전체 | SYNTH_TIMING_PASS | ✅ | STAGE 1~4 비트스트림 · 2026-11-23 |
| 장 전체 | XSIM_RTL_PASS | ✅ | Vivado Simulator v2024.2.0 · Icarus와 같은 TB·판정 줄 · 2026-11-23 · p04/validation/xsim_rtl_20261123.log |
| 장 전체 | BOARD_PASS | ⏳ | ⚠ 미실시 · 실물 보드 확인 대기 |
| 4-1 INT8·INT16 정밀도 비교 | HOST_MODEL_PASS | ✅ | PYTHON_FIXED_SELF_TEST_PASS |
| 4-1 INT8·INT16 정밀도 비교 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS PRECISION cycles=2020 · 도구 버전 미기록 · 2026-11-18 |
| 4-1 INT8·INT16 정밀도 비교 | SYNTH_TIMING_PASS | ✅ | ch06 precision_compare WNS=8.710 WHS=0.230 LUT=323 FF=27 DSP48E1=0 RAM… · 2026-11-20 |
| 4-1 INT8·INT16 정밀도 비교 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 4-1 INT8·INT16 정밀도 비교 | 장 Top STAGE=1 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 4-1 INT8·INT16 정밀도 비교 | 장 Top STAGE=1 합성·타이밍 | ✅ | 통과 · WNS=0.583 WHS=0.024 DRC_ERRORS=0 LUT=814 FF=390 DSP48E1=0 RAMB18=0 |
| 4-2 784 입력 13타일 누산 (INT8) | HOST_MODEL_PASS | ✅ | PYTHON_TILE784_SELF_TEST_PASS suite=full cases=26 tiles=13 last_len=16 acc_w=41 bias_w=40 … |
| 4-2 784 입력 13타일 누산 (INT8) | RTL_SIM_PASS | ✅ | RTL_SIM_PASS TILE784 cases=26 tiles=13 tile_go_to_accept_cyc… 외 2건 · Vivado Simulator 2024.2.0 · 날짜 미기록 |
| 4-2 784 입력 13타일 누산 (INT8) | SYNTH_TIMING_PASS | ✅ | OOC 배선 후 WNS +0.712 ns (구 19장 OOC 기록) · <code>part03/ch19/validation/synth_ooc_summary.md</code> |
| 4-2 784 입력 13타일 누산 (INT8) | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 4-2 784 입력 13타일 누산 (INT8) | 장 Top STAGE=2 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 4-2 784 입력 13타일 누산 (INT8) | 장 Top STAGE=2 합성·타이밍 | ✅ | 통과 · WNS=0.423 WHS=0.035 DRC_ERRORS=0 LUT=3966 FF=2790 DSP48E1=4 RAMB18=4 |
| 4-3 INT8·INT16 MNIST 정밀도 | HOST_MODEL_PASS | ✅ | PYTHON_TILE784_SELF_TEST_PASS suite=full cases=26 tiles=13 last_len=16 acc_w=41 bias_w=40 … |
| 4-3 INT8·INT16 MNIST 정밀도 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS TILE784 cases=26 tiles=13 tile_go_to_accept_cyc… 외 4건 · Vivado Simulator 2024.2.0 · 날짜 미기록 |
| 4-3 INT8·INT16 MNIST 정밀도 | SYNTH_TIMING_PASS | ✅ | OOC 배선 후 WNS +0.625 ns (구 19장 OOC 기록) · <code>part03/ch19/validation/synth_ooc_summary.md</code> |
| 4-3 INT8·INT16 MNIST 정밀도 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 4-3 INT8·INT16 MNIST 정밀도 | 장 Top STAGE=3 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 4-3 INT8·INT16 MNIST 정밀도 | 장 Top STAGE=3 합성·타이밍 | ✅ | 통과 · WNS=0.201 WHS=0.036 DRC_ERRORS=0 LUT=6488 FF=4638 DSP48E1=8 RAMB18=9 |
| 4-4 PE 병렬도·메모리 구조 | HOST_MODEL_PASS | ✅ | PYTHON_ARCH_SELF_TEST_PASS samples=4 tile_runs=52 cycles PE1=700 PE4=206 PE8=138 load_w=64… |
| 4-4 PE 병렬도·메모리 구조 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS PE_SCALE tile_runs=52 PE1=70x10 PE4=206 PE8=138… · Vivado Simulator 2024.2.0 · 날짜 미기록 |
| 4-4 PE 병렬도·메모리 구조 | SYNTH_TIMING_PASS | ✅ | OOC 배선 후 5구성 WNS 최소 +0.901 ns (OOC) · <code>part03/ch19/validation/synth_ooc_summary.md</code> |
| 4-4 PE 병렬도·메모리 구조 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 4-4 PE 병렬도·메모리 구조 | 장 Top STAGE=4 시뮬레이션 | ✅ | 응답 바이트 단위 대조 |
| 4-4 PE 병렬도·메모리 구조 | 장 Top STAGE=4 합성·타이밍 | ✅ | 통과 · WNS=0.195 WHS=0.036 DRC_ERRORS=0 LUT=7401 FF=5536 DSP48E1=21 RAMB18=22 |

## 5장 · MicroBlaze V SoC ([p05_mbv_soc_v01.html](../p05_mbv_soc_v01.html))

| 구분 | 게이트 | 상태 | 근거 |
|---|---|---|---|
| 장 전체 | RTL_SIM_PASS | ✅ | 서브젝트 시뮬레이션·정적 검사 모두 통과 |
| 장 전체 | SYNTH_TIMING_PASS | ✅ | WNS +0.374 ns · WHS +0.034 ns (21장 SoC 배선 후, 안 A) · part03/ch21/validation/soc_summary.md |
| 장 전체 | BOARD_PASS | ⏳ | 미실시 · 보드 점검표 B1~B7 대기 |
| 5-1 AXI4-Lite NPU IP | HOST_MODEL_PASS | — | 해당 없음 (Python 기준 모델 없음) |
| 5-1 AXI4-Lite NPU IP | RTL_SIM_PASS | ✅ | RTL_SIM_PASS AXI_NPU inferences=7 axi_writes=67451 axi_reads… · Vivado Simulator 2024.2.0 · 2026-11-18 |
| 5-1 AXI4-Lite NPU IP | SYNTH_TIMING_PASS | ✅ | OOC 배선 후 WNS +0.223 ns (OOC) · part03/ch20/validation/synth_ooc_summary.md |
| 5-1 AXI4-Lite NPU IP | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 5-2 MicroBlaze V SoC 연결 | HOST_MODEL_PASS | — | 해당 없음 (Python 기준 모델 없음) |
| 5-2 MicroBlaze V SoC 연결 | RTL_SIM_PASS | — | 해당 없음 (RTL 시뮬레이션 대상 아님) · 정적 검사: CHECK_PASS post-route setup/hold met · 2026-11-19 |
| 5-2 MicroBlaze V SoC 연결 | SYNTH_TIMING_PASS | ✅ | WNS +0.374 ns · WHS +0.034 ns (SoC 배선 후, 비트스트림 생성) · part03/ch21/validation/soc_summary.md |
| 5-2 MicroBlaze V SoC 연결 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 5-2 MicroBlaze V SoC 연결 | 보드 점검표 | ⏳ | B1·B4b·B4c 미실시 |
| 5-3 C 드라이버와 표시 | HOST_MODEL_PASS | — | 해당 없음 (Python 기준 모델 없음) |
| 5-3 C 드라이버와 표시 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS DRIVER_BRIDGE axi_writes=35917 axi_reads=3781 i… · Icarus Verilog 12.0 · 2026-11-19 |
| 5-3 C 드라이버와 표시 | SYNTH_TIMING_PASS | — | 해당 없음 |
| 5-3 C 드라이버와 표시 | VITIS_ELF_PASS | ✅ | VITIS_ELF_PASS (빌드만, 실물 실행은 사용자와 함께) · part03/ch22/validation/build_vitis.log |
| 5-3 C 드라이버와 표시 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 5-3 C 드라이버와 표시 | 보드 점검표 | ⏳ | B2·B3·B4·B4a 미실시 |
| 5-4 CPU·NPU 추론 시간 | HOST_MODEL_PASS | — | 해당 없음 (Python 기준 모델 없음) |
| 5-4 CPU·NPU 추론 시간 | RTL_SIM_PASS | ✅ | SOC_RTL_SIM_PASS · Vivado 2024.2 xsim (21장 SoC 전체 + ELF) · 2026-11-19 |
| 5-4 CPU·NPU 추론 시간 | SYNTH_TIMING_PASS | — | 해당 없음 |
| 5-4 CPU·NPU 추론 시간 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 5-4 CPU·NPU 추론 시간 | 보드 점검표 | ⏳ | B5·B6·B7 미실시 |
| 5-5 자원·타이밍 스윕 | HOST_MODEL_PASS | — | 해당 없음 (Python 기준 모델 없음) |
| 5-5 자원·타이밍 스윕 | RTL_SIM_PASS | — | 해당 없음 (RTL 시뮬레이션 대상 아님) · 정적 검사: SWEEP_SUMMARY pe4_int8=146.1MHz pe4_int16=126.4MHz tile784_i… · 2026-11-18 |
| 5-5 자원·타이밍 스윕 | SYNTH_TIMING_PASS | ✅ | OOC 배선 후 WNS +0.476 ns (10 ns 스윕 첫 줄) · part03/ch24/validation/timing_sweep.md |
| 5-5 자원·타이밍 스윕 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 5-6 전력·추론당 에너지 | HOST_MODEL_PASS | — | 해당 없음 (Python 기준 모델 없음) |
| 5-6 전력·추론당 에너지 | RTL_SIM_PASS | ✅ | SOC_RTL_SIM_PASS · Vivado 2024.2 xsim (21장 SoC 전체 + ELF) · 2026-11-19 |
| 5-6 전력·추론당 에너지 | SYNTH_TIMING_PASS | — | 해당 없음 |
| 5-6 전력·추론당 에너지 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 5-7 시스템 통합 | HOST_MODEL_PASS | — | 해당 없음 (Python 기준 모델 없음) |
| 5-7 시스템 통합 | RTL_SIM_PASS | — | 해당 없음 (RTL 시뮬레이션 대상 아님) · 정적 검사: / sw_build_ch31 / PASS / · 2026-11-19 |
| 5-7 시스템 통합 | SYNTH_TIMING_PASS | — | 해당 없음 |
| 5-7 시스템 통합 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |

## 6장 · 응용 확장 ([p06_npu_apps_v01.html](../p06_npu_apps_v01.html))

| 구분 | 게이트 | 상태 | 근거 |
|---|---|---|---|
| 장 전체 | RTL_SIM_PASS | ✅ | 서브젝트 시뮬레이션·정적 검사 모두 통과 |
| 장 전체 | SYNTH_TIMING_PASS | ✅ | WNS +0.374 ns · WHS +0.034 ns (21장 SoC 배선 후, 안 A — 6-1·6-3·6-5 공용) · part03/ch21/validation/soc_summary.md |
| 장 전체 | BOARD_PASS | ⏳ | 미실시 · 보드 점검표 B9~B26a 대기 |
| 6-1 손글씨 숫자 인식 (공통) | HOST_MODEL_PASS | ✅ | DIGIT_REFERENCE_SELFTEST_PASS model_id=f16c4f12 frame_bytes=795 |
| 6-1 손글씨 숫자 인식 (공통) | RTL_SIM_PASS | ✅ | RTL_SIM_PASS FND_SCAN vectors=36 digit_changes=9 외 1건 · Icarus Verilog 12.0 · 2026-11-19 |
| 6-1 손글씨 숫자 인식 (공통) | SYNTH_TIMING_PASS | — | 해당 없음 |
| 6-1 손글씨 숫자 인식 (공통) | ELF_MEM_PASS | ✅ | ELF_MEM_PASS · part03/ch28/validation/build_sw.log |
| 6-1 손글씨 숫자 인식 (공통) | SOC28_RTL_SIM_PASS | ✅ | SOC28_RTL_SIM_PASS checks=15/15 · part03/ch28/validation/soc_sim_mapA_20261120.log |
| 6-1 손글씨 숫자 인식 (공통) | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 6-1 손글씨 숫자 인식 (공통) | 보드 점검표 | ⏳ | B9·B10·B11·B12·B13·B13a 미실시 |
| 6-2 3×3 합성곱 (선택) | HOST_MODEL_PASS | ✅ | PYTHON_CONV_SELF_TEST_PASS frames=26 out=6x6 macs_per_frame=324 first_spec=-6 seed=2626 |
| 6-2 3×3 합성곱 (선택) | RTL_SIM_PASS | ✅ | RTL_SIM_PASS CONV3X3 frames=26 outputs_per_frame=36 latency=… · Vivado Simulator 2024.2.0 · 2026-11-18 |
| 6-2 3×3 합성곱 (선택) | SYNTH_TIMING_PASS | ✅ | OOC 배선 후 WNS +4.647 ns (OOC) · part03/ch26/validation/synth_ooc_summary.md |
| 6-2 3×3 합성곱 (선택) | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 6-3 센서 상태 감시 | HOST_MODEL_PASS | ✅ | SENSOR_REFERENCE_SELFTEST_PASS model_id=18496ca4 frame_bytes=65 |
| 6-3 센서 상태 감시 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS ALARM_POLICY cycles=4070 fault_entries=99 ack_o… 외 1건 · Icarus Verilog 12.0 · 2026-11-19 |
| 6-3 센서 상태 감시 | SYNTH_TIMING_PASS | ✅ | OOC 배선 후 WNS +6.711 ns (OOC) · part03/ch29/validation/synth_ooc_summary.md |
| 6-3 센서 상태 감시 | ELF_MEM_PASS | ✅ | ELF_MEM_PASS · part03/ch29/validation/build_sw.log |
| 6-3 센서 상태 감시 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 6-3 센서 상태 감시 | 보드 점검표 | ⏳ | B14·B15·B16·B17·B17a 미실시 |
| 6-4 모터 안전 (가상 부하) | HOST_MODEL_PASS | ✅ | MOTOR_REFERENCE_SELFTEST_PASS |
| 6-4 모터 안전 (가상 부하) | RTL_SIM_PASS | ✅ | RTL_SIM_PASS MOTOR_SAFETY cycles=125968 ena_cycles=10364 tri… 외 1건 · Icarus Verilog 12.0 · 2026-11-19 |
| 6-4 모터 안전 (가상 부하) | SYNTH_TIMING_PASS | ✅ | OOC 배선 후 WNS +3.699 ns (OOC) · part03/ch30/validation/synth_ooc_summary.md |
| 6-4 모터 안전 (가상 부하) | ADDR_MAP_A_PASS | ✅ | ADDR_MAP_A_PASS · part03/ch30/validation/build_soc_mapA_20261120.log |
| 6-4 모터 안전 (가상 부하) | ELF_MEM_PASS | ✅ | ELF_MEM_PASS · part03/ch30/validation/build_soc_mapA_20261120.log |
| 6-4 모터 안전 (가상 부하) | SOC_TIMING | ✅ | WNS 0.357 ns · WHS 0.030 ns (30장 SoC 배선 후, 안 A) · part03/ch30/validation/build_soc_mapA_20261120.log |
| 6-4 모터 안전 (가상 부하) | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 6-4 모터 안전 (가상 부하) | 보드 점검표 | ⏳ | B18·B19·B20·B21·B22·B23·B23a·B23b 미실시 |
| 6-5 보안 모델 적재 | HOST_MODEL_PASS | ✅ | SECURE_REFERENCE_SELFTEST_PASS aes_kat=2 ctr_kat=1 sha_kat=2 hmac_kat=2 cross=cryptography… |
| 6-5 보안 모델 적재 | RTL_SIM_PASS | ✅ | RTL_SIM_PASS AES128 blocks=204 kat=6 cycles_per_block=11 외 2건 · Icarus Verilog 12.0 · 2026-11-19 |
| 6-5 보안 모델 적재 | SYNTH_TIMING_PASS | ✅ | OOC 배선 후 2구성 WNS 최소 +0.117 ns (OOC) · part03/ch31/validation/synth_ooc_summary.md |
| 6-5 보안 모델 적재 | ELF_MEM_PASS | ✅ | ELF_MEM_PASS · part03/ch31/validation/build_sw.log |
| 6-5 보안 모델 적재 | BOARD_PASS | ⏳ | ⚠ 미실시 · 현재 실물 보드 확인 불가 |
| 6-5 보안 모델 적재 | 보드 점검표 | ⏳ | B25·B26·B26a 미실시 |
