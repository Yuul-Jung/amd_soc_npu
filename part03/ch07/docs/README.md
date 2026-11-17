# P3-07 스트리밍 벡터 내적 계약

`vector_dot_core(DATA_WIDTH=16, ACC_WIDTH=40, MAX_LEN=256)`.
clk/resetn, start_i, length_i[8:0], valid_i, signed a_i/b_i 입력.
ready_o/busy_o/done_o/error_o와 signed result_o 출력.
idle에서 start 수락. 길이0은 즉시 done/result0. 길이>MAX_LEN은 error 펄스로 거부.
busy 중 start는 무시. 데이터 수락은 valid_i && ready_o일 때만 한다.
수락 입력 N개 이후 마지막 입력 에지 k+1 직후 result/done을 출력한다.
done/error는 한 에지 펄스이며 결과는 다음 완료까지 유지한다.
Reset은 계산을 취소한다. 누산은 01장 mac_core와 같은 signed 순환 연산이다.
길이 신호는 0..256 범위 표현이며 MAX_LEN은 1..256으로 제한한다.
이 장에는 메모리 전송을 넣지 않는다. 상위 계층이 입력·가중치를 순서대로 공급한다.

```bash
bash part03/ch07/scripts/run_sim.sh
```

INT16/40 및 INT8/32, 길이0/1/2/4/16/256, extrema·랜덤·버블·busy 중 start·Reset/재시작을 검증한다.
합성·타이밍·보드 미수행.
