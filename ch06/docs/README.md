# P3-06 동일 실수 입력의 INT8/INT16 비교

`precision_compare(SATURATE=1)`는 32비트 signed Q*.12 원본 `x_i`를
INT8 소수부4비트와 INT16 소수부8비트로 각각 tie-away 반올림한다.
같은 05장 fixed_quantizer를 SHIFT8/SHIFT4로 재사용한다.
포트: clk/resetn/valid_i/x_i → q8_o/q16_o/overflow8_o/overflow16_o/valid_o.
상승 에지 수락 직후 결과 유효, idle 유지/Valid=0, 동기 Reset 우선.
SATURATE=0 비교 인스턴스는 동일 반올림 후 각 출력 폭으로 순환한다.
공통 Q12 기준 오차는 `q8*256-x`, `q16*16-x`이며 단위는 1/4096이다.
정확히 표현 가능한 입력, 반올림 오차가 다른 입력, 범위 초과 입력을 구분한다.
CSV는 실제 RTL trace 비교가 통과한 모델 결과이며 자원/타이밍 비교가 아니다.

```bash
bash part03/ch06/scripts/run_sim.sh
```

validation/precision_comparison.csv와 배치 요약을 확인한다. 합성·보드 미수행.
