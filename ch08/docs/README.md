# P3-08 네 PE와 합산 트리

`pe_array4(DATA_WIDTH=16,ACC_WIDTH=40)`는 07장 vector_dot_core 네 개를 재사용한다.
start_i/length_i는 공통이며 valid_i[3:0]·ready_o[3:0]는 PE별 독립이다.
a_i/b_i는 4*DATA_WIDTH packed 버스이고 낮은 슬라이스가 PE0다.
각 PE는 length_i개 입력을 수락한다. 일부 Valid만 있어도 다른 PE의 진척을 막지 않는다.
먼저 끝난 PE 결과를 보관하고 네 done을 모두 모은 뒤 결과를 함께 공개한다.
pe_results_o는 PE0부터 낮은 4*ACC_WIDTH 슬라이스, sum_o는 signed ACC_WIDTH+2비트다.
합산은 2개씩 더한 후 최종 합을 내는 확장 가산 트리이며 PE별 누산은 기존 폭으로 순환한다.
start/busy/done/error, 동기 Reset, 길이0/최대256, busy 중 start 무시는 07장과 같다.
마지막 PE의 done이 관측된 다음 에지에 sum/done을 등록한다. 입력 유효 패턴에 따라 총 지연이 달라진다.
상위 계층은 각 ready&&valid를 독립적으로 계산해야 한다.

```bash
bash part03/ch08/scripts/run_sim.sh
```

Python은 PE별 07장 dot 정답과 넓은 정수 합을 사용한다. 합성·성능 주장은 하지 않는다.
