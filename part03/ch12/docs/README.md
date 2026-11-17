# 제12장 · PC UART → 실제 DSP 4PE NPU 종합 실습

- 준비: Basys3 100MHz CLK, UART RX B18/TX A18, btnC Reset U18, LED/FND.
- 단순 명령 '0'..'3' 입력 시 Controller가 2원소·4뉴런 가중치를 실제 메모리 쓰기 포트로 기록한다.
- `npu_engine4`가 동기 BRAM 읽기→`dsp_multiplier` 등록 곱→`npu_dsp_mac_lane` 누산→signed 41bit 점수→argmax4를 수행한다.
- 터미널 응답: `Ck:HHHHHHHHHHH,HHHHHHHHHHH,HHHHHHHHHHH,HHHHHHHHHHH\\r\\n`.
- 출력 FND는 0000~0003, LED0~3 onehot, LED13 Busy, LED14 DONE latch, LED15 Error latch.
- `run_demo.sh`에서 실제 UART TX 비트파형을 Testbench가 UART RX 모니터로 복조·검사하고, CSV를 PC 정수 모델로 대조한다.
- 이 페이지는 제작 절차 및 기대 결과를 설명하며 Vivado 합성/실물 PASS를 주장하지 않는다.
