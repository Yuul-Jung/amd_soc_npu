# 표준 7세그먼트 IP (handoff)

- 출처: 같은 사용자의 SoC 실습 시리즈 N01 (`ip_seg7` 1.0, IP 표준 개정 1). 동결 주소맵 [06] SEG7 0x4006_0000.
- 파일: `ip_seg7.v` (기능), `axil_slave.v`·`ip_std.v` (IP 표준 공통 모듈, 고치지 않음).
- 레지스터: VALUE 0x0000 (16진수 4자리), MODE 0x0004 ([3:0] 원시, [11:8] 끔), RAW 0x0008, DP 0x000C, ID 0xFFF0 = 0x53454737 ("SEG7").
- 웹 확인 (2026-11-19, Icarus Verilog 12): ID·VALUE·MODE·RAW 쓰기/읽기 → `SEG7_TB_PASS`. 합성·보드는 ⚠ 미검증.
- VS Code는 이 폴더를 `part03/common/rtl/ip_std/`로 복사해 쓴다 (`../VSCODE_DIRECTIVE_A.md` 3절).
