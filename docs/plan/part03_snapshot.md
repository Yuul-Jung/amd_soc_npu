# part03/ 사본 (VS Code 판에서 가져온 파일)

3장부터 서브젝트 코드 기준은 VS Code 판이다 (`docs/PROJECT_PLAN.md` 6절). VS Code 브랜치는 main과 기준이 크게 달라 통째로 합치지 않고, 장 Top이 쓰는 파일만 **같은 경로 그대로, 내용 수정 없이** 가져온다.

| 가져온 날 | VS Code 커밋 | 경로 | 쓰는 곳 |
|---|---|---|---|
| 2026-11-19 | `9203bfa` | `part03/ch13`~`ch16` 전체 (rtl·tb·reference·scripts·docs·validation) | 3장 서브젝트 3-1~3-4 |
| 2026-11-19 | `9203bfa` | `part03/host_tools/p3_integer_reference.py` · `test_p3_integer_reference.py` | 13~16장 기준 모델 |
| 2026-11-19 | `9203bfa` | `part03/ch02/rtl/dsp_multiplier.v` · `part03/mini_npu/rtl/npu_dsp_mac_lane.v` | 14장 코어 (우리 `ch02/`·`mini_npu/`와 바이트까지 같음) |
| 2026-11-19 | `9203bfa` | `part03/ch17`~`ch19` 전체 · `part03/ch04/rtl/bram_sync_buffer.v` (우리 `ch04/`와 같음) | 4장 서브젝트 4-2~4-4 |
| 2026-11-19 | `ddaaf66` | `part03/ch20`~`ch25` · `ch27` 전체 · `part03/common` (rtl/ip_std · sw/p3_seg7.h · tb · validation) | 5장 서브젝트 5-1~5-7 (안 A 동결 주소맵) |
| 2026-11-19 | `ddaaf66` | `part03/ch26` · `ch28`~`ch31` 전체 | 6장 서브젝트 6-1~6-5 |
| 2026-11-20 | `e9e0425` | `part03/ch25` · `ch27` · `ch28` · `ch30` 변경분 (25장 안 A 전력, 27장 보고서·run_all fpga·점검표 B23b, 28장 안 A SoC xsim, 30장 안 A 재빌드) | 5-6 · 6-1 · 6-4 ⚠ 해제 |
| 2026-11-23 | `fe7b0df` | `part03/ch13`~`ch31` · `common` · `host_tools` · `mini_npu` 변경분 157개 (주석·docstring 정리, `common/scripts/p3_sim.sh` 추가와 13~20·26장 `run_sim.sh`, 점검표 문구) | 3~6장 코드 상자·보드 확인 표 |
| 2026-11-23 | `60b0b3f` | `part03/ch13`~`ch20`·`ch26`·`ch31` `validation/rtl_sim.log`(xsim 기록), `ch27` 회신·`run_all_summary.md`, `common/scripts/p3_sim.sh` (PR #11 병합) | 검증 현황 도구 줄 |
| 2026-11-23 | `95c7d92` | 22·28~31장 `run_sim.sh`(Vivado 시뮬레이터 지원)와 `validation/rtl_sim.log`, 문자열 속 옛 장 번호 정리 50개 파일 (PR #14 병합) | 5·6장 코드 상자, 검증 현황 도구 줄 |

규칙
- 웹 쪽은 이 파일들을 고치지 않는다. 고칠 일이 생기면 VS Code 판에서 고치고 다시 가져온다.
- 4단계(main 병합) 때 VS Code 판 최신 커밋과 다시 대조한다. 그 사이 VS Code가 같은 파일을 바꿨으면 그쪽을 따르고 장 Top 시뮬레이션을 다시 돌린다.
- 가져온 뒤 이 저장소에서 다시 실행한 결과: 13~19장 `run_sim.sh` 모두 PASS, 20·22·26·28~31장 `run_sim.sh` PASS (2026-11-19, 28~30장은 협동 시뮬레이션·변이 시험이라 각 6~13분). 21·23~25장은 Vivado·Vitis 빌드라 VS Code 기록을 그대로 쓴다.
