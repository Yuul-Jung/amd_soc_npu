# 준비 단계 · 100MHz Basys3 115200/8N1 UART Echo

- 물리 RX → 2FF 동기화 → Byte Stream → UART Echo Controller → 물리 TX.
- `basys3_uart_echo_top`은 순수 Shell이며 기능은 하위 모듈에 둡니다.
- 테스트벤치: 외부 RX 라인에 'A', '5' 비트를 인가하고 TX 출력 비트 자체를 UART RX로 복조하여 판정.
- VS Code 실행: `bash part03/ch00/scripts/run_sim.sh` (Icarus Verilog 필요).
- 보드 다운로드는 후반 일괄 검증. 실행 로그 없는 현재 상태는 RTL_SIM_NOT_RUN.
