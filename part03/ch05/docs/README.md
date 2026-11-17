# P3-05 고정소수점 축소 계약

`fixed_quantizer(IN_WIDTH=32, OUT_WIDTH=8, SHIFT=8, ROUND=1, SATURATE=1)`.
포트: clk/resetn/valid_i, signed x_i, signed q_o, valid_o, overflow_o.
기본 Q 입력은 소수부 8비트이며 출력은 정수(Q*.0)다. 일반적으로 출력 소수부는
입력 소수부-SHIFT다. SHIFT>=0, ROUND=0은 산술 우시프트(음수도 -무한대로 절삭),
ROUND=1은 최근접·정확히 절반이면 0에서 멀어지는 반올림이다.
SATURATE=1은 출력 min/max로 포화, 0은 하위 비트 순환. overflow_o는 축소 전 범위 초과다.
SHIFT=0도 지원한다. 지원 폭 IN=2..48, OUT=2..32, SHIFT=0..30.
출력은 수락 상승 에지 직후 유효. 동기식 Active-Low Reset 우선이며 idle은 값/overflow 유지·Valid=0.
동일 입력에 절삭/반올림 × 포화/순환 네 구성을 병렬 비교한다. 기존 MAC은 수정하지 않는다.

```bash
bash part03/ch05/scripts/run_sim.sh
```

RTL은 64비트 부호 확장 중간값을 사용하여 음수 논리 시프트와 산술 시프트를 혼동하지 않는다.
이는 기능 표현이며 합성·자원·타이밍·보드는 미검증이다.
