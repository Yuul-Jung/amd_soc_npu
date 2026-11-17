# P3-09 4뉴런 Dense Layer

`dense_layer4(DATA_WIDTH=16,ACC_WIDTH=40,SHIFT=0)`는 08장 4PE와 05장 양자화기를 재사용한다.
한 벡터의 x_i를 네 뉴런에 공통 공급하고 weights_i는 낮은 슬라이스부터 뉴런0..3이다.
동일 에지의 valid_i&&ready_o에서 x 하나와 가중치4개를 수락한다. 입력 길이는 0..64.
biases_i는 4*ACC_WIDTH signed packed 값이며 start 수락 때 저장한다.
PE별 순환 내적(기존 ACC_WIDTH) + Bias를 ACC_WIDTH+1로 더하고 음수는 ReLU로 0 처리한다.
그다음 tie-away 반올림/포화 양자화로 DATA_WIDTH 출력, overflow_o[3:0]을 제공한다.
SHIFT=0은 정수 그대로이며 다른 SHIFT의 Q 규칙은 05장을 따른다.
지원 실습 구성은 16/40과 8/32다. ready가 0이면 데이터는 수락되지 않는다.
Reset은 계산/저장 Bias를 취소한다. busy 중 start는 무시, 길이>64는 error 펄스로 거부.
result_o는 낮은 슬라이스가 뉴런0. done은 모든 결과가 정렬된 한 에지 펄스다.
한 요청당 정확히 length_i 전송을 공급한 후 done을 기다린다.
실제 메모리 용량은 상위에서 입력64개, 가중치4×64개가 필요하다(10장 통합).

```bash
bash part03/ch09/scripts/run_sim.sh
```

Python은 전체 층 출력 4개를 정수 산술로 계산한다. RTL의 총 지연/타이밍은 합성 성능 주장이 아니다.
