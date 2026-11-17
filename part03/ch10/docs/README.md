# P3-10 독립 소형 NPU Core 계약

`npu_core(DATA_WIDTH=16,ACC_WIDTH=40)`는 1개 입력 버퍼와 4개 가중치 버퍼,
07장 내적→08장 PE→09장 Bias/ReLU/포화 경로를 통합한다. AXI·CPU·보드 결합은 없다.
지원된 INT8 비교 구성은 8/32다. 한 벡터 길이는0..64, 뉴런은4개, SHIFT=0 정수 추론이다.

| 포트 | 계약 |
|---|---|
| clk/resetn | 상승 에지, 동기 Active-Low Reset |
| x_wr_en/x_wr_addr[5:0]/x_wr_data | 입력64단어 적재 |
| w_wr_en/w_neuron[1:0]/w_wr_addr[5:0]/w_wr_data | 뉴런별64단어 가중치 적재 |
| load_ready_o | Reset 해제 및 idle에서1, 적재는 이때만 수락 |
| start_i/length_i[8:0]/biases_i[4*ACC_WIDTH-1:0] | idle에서 시작·길이·Bias 저장 |
| busy_o/done_o/error_o | 실행 상태, 한 에지 완료/오류 펄스 |
| result_o[4*DATA_WIDTH-1:0]/overflow_o[3:0] | 뉴런0부터 낮은 슬라이스, 완료 후 유지 |

요청 길이의 모든 입력/가중치 주소는 먼저 적재해야 한다. 미기록 주소 읽기는
호출자 계약 위반이며 04장처럼 정의하지 않는다. 코어에 자동 메모리 초기화는 없다.
각 BRAM 깊이는64로 구성하여 총320단어(기본640byte), Bias4×40비트(20byte)가 필요하다.
길이>64 또는 idle의 start와 적재 동시 요청은 error로 시작을 거부한다.
busy 중 start는 무시하며 쓰기도 수락하지 않는다. Reset은 계산만 취소하고 메모리는 보존한다.
Reset 중 적재도 무시한다. Reset 이후 사용자는 이전 적재 데이터로 다시 시작할 수 있다.

FSM 순서: IDLE→LAUNCH→READ→WAIT_READ→SEND→(다음READ 또는 WAIT_DONE)→IDLE.
READ 에지에 BRAM이 데이터를 등록하고 WAIT_READ 에지에 rd_valid를 확인한다.
SEND에서는 Dense의 ready&&valid로 동일 주소의 입력/가중치4개를 수락한다.
read/write는 FSM상 분리하여 같은 주소 충돌이 발생하지 않는다.
길이0은 메모리 읽기 없이 Bias/ReLU 결과를 낸다. done은 실제 Dense 완료 이후다.
처리 지연은 기능 시뮬레이션에서만 확인하며 물리 MHz/자원 절감 주장은 하지 않는다.

```bash
bash part03/ch10/scripts/run_sim.sh
```

Python은 주소별 적재 이미지로부터 전체 층을 계산한다. TB는 역순 적재, 정상 실행,
계산 중 적재 차단, Reset 취소·데이터 보존·재시작을 검증한다.
합성·타이밍·Vitis·Basys3는 후반 일괄 검증 대상이다.
