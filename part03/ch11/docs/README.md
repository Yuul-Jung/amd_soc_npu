# 제11장 · UART로 X/W/B 직접 기록하기

1. 기존 UART Echo의 RX 데이터와 12장 NPU Controller를 연결한다.
2. `X addr hi lo` → 64개 입력 메모리 중 한 주소 기록.
3. `W neuron addr hi lo` → 4뉴런의 지정 가중치 메모리 기록.
4. `B neuron b4 b3 b2 b1 b0` → Bias 40비트 big-endian 기록.
5. `R len` → 현재 모델의 length=1..64로 추론을 시작한다. 모든 필요한 X/W 주소가 유효해야 한다.
6. `OK\\r\\n`/`ERR\\r\\n`/`Ck:...\\r\\n` 응답이 끝난 뒤 다음 명령을 보낸다.
7. NPU Busy 시 부정확한 덮어쓰기는 허용하지 않는다. 본 구현은 전체 프레임 CRC·재전송은 지원하지 않는다.

테스트는 `part03/mini_npu/tb/tb_npu_uart.sv`의 Bias 변경 뒤 분류가 실제로 바뀌는 항목을 확인한다. 구체적인 API/클록/데이터 폭은 전체 RTL 원본과 동일해야 한다.
