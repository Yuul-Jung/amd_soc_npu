# 27장 run_all 결과 (LEVEL=fpga, 2026-11-20T01:02Z, commit d484dfe)

| 단계 | 결과 |
|---|---|
| host_integer_reference | PASS |
| rtl_ch13_26 | PASS |
| pc_eval_ch18 | PASS |
| synth_ch19 | PASS |
| synth_ch20 | PASS |
| package_ip_ch20 | PASS |
| soc_build_ch21 | PASS |
| vitis_ch22 | PASS |
| synth_ch26 | PASS |
| sw_build_ch28 | PASS |
| synth_ch29 | PASS |
| sw_build_ch29 | PASS |
| synth_ch30 | PASS |
| soc_build_ch30 | PASS |
| synth_ch31 | PASS |
| sw_build_ch31 | PASS |
| sweep_ch24 | NOT_RUN (LEVEL=fpga) |
| soc_sim_ch23 | NOT_RUN (LEVEL=fpga) |
| power_ch25 | NOT_RUN (LEVEL=fpga) |
| soc_sim_ch28 | NOT_RUN (LEVEL=fpga) |

실물 Basys3 검증은 포함하지 않는다(docs/BOARD_CHECKLIST.md).

## 재현 비교 (2026-11-20, 별도 git worktree에서 처음부터 빌드)

저장소 산출물(점검표 SHA가 가리키는 `build/`)을 덮어쓰지 않도록 같은 커밋의 별도 worktree에서 실행했다.

| 항목 | 기록된 빌드 | 이번 재빌드 |
|---|---|---|
| 21장 SoC 배선 후 | WNS +0.374 · WHS +0.034 ns | 같음 |
| 30장 SoC 배선 후 | WNS +0.357 · WHS +0.030 ns | 같음 |
| ELF 크기 (digit·sensor·secure·motor) | 36,276 · 39,372 · 61,556 · 53,748 B | 같음 |
| bit·XSA·ELF SHA-256 | 점검표 값 | 다름 — 빌드 시각·경로가 파일에 들어가므로 예상한 차이. 보드 확인은 점검표 SHA의 원래 빌드로 한다 |

`sweep_ch24`·`soc_sim_ch23`·`power_ch25`는 이미 안 A로 실행한 기록이 있다(각 장 `validation/`). `soc_sim_ch28`은 따로 재실행 중(`ch28/validation/soc_sim_mapA_20261120.log`).
