# 제3부 08장 · 4PE

## 1. 이번 장에서 실제 만드는 기능

- 실제 RTL: `part03/ch08/rtl/pe_array4.v`
- 기능: 4개 뉴런 독립 dot 및 완료 정렬.
- 기존 정상 소스·테스트벤치·검증 기록은 보존하고 신규 누적 NPU와 혼동하지 않는다.

## 2. VS Code 따라하기

1. 저장소 루트에서 `part03/ch08/rtl/pe_array4.v`와 같은 장의 `tb/`를 열어 포트·신호를 확인한다.
2. 아래 명령을 실행한다.

```bash
# 08장 원본 RTL과 Python 참조 모델의 독립 시뮬레이션 실행
bash part03/ch08/scripts/run_sim.sh
```

3. 검증 포인트: 4개 개별 점수와 sum 신호 혼동 금지.
4. RTL 값과 예상 출력의 차이를 확인하고, 실패하면 소스·테스트벤치·로그를 함께 보존한다.

## 3. 완료 기준과 검증 경계

- `part03/ch08/validation/rtl_sim.log`는 기존 과거 독립 실행 기록이며 이 문서 작성으로 새로 실행한 것은 아니다.
- 실제 UART→BRAM→DSP 등록 곱→4PE→Argmax·TX 연결은 제11~12장 별도 신규 통합 경로에서 검증한다.
- 실제 Vivado 합성/타이밍 및 Basys3 실물은 증거 확보 전 NOT_RUN.
