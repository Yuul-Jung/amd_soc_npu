# 준비 단계 · 100MHz Basys3 115200/8N1 UART Echo

- 물리 RX → 2FF 동기화 → Byte Stream → UART Echo Controller → 물리 TX.
- `basys3_uart_echo_top`은 순수 Shell이며 기능은 하위 모듈에 둡니다.
- 테스트벤치: 외부 RX 라인에 'A', '5' 비트를 인가하고 TX 출력 비트 자체를 UART RX로 복조하여 판정.
- VS Code 실행: `bash part03/ch00/scripts/run_sim.sh` (Icarus Verilog 필요).
- `uart_core`는 RX/TX 각 16바이트 FIFO 포함. Reset·Framing error·FIFO 경계는 `bash part03/mini_npu/scripts/run_adversarial.sh`로 확인.
- 2026-11-17 로컬 Icarus 12.0 실행: `UART_ECHO_RTL_SIM_PASS decoded=2` (`part03/validation/P3_00_12_LOCAL_RTL_SIM_20261117_v01.md`). 보드 다운로드는 후반 일괄 검증.
