# VS Code → 웹 회신 (2026-11-23)

## 1. 지시 15 1단계 — 1~4장 장 Top xsim RTL 시뮬레이션: PASS

- 브랜치 `vscode/xsim-stage1` (main b932f7d 기준). 도구: Vivado Simulator v2024.2.0.
- 실행: `for p in p01 p02 p03 p04; do SIM=xsim bash $p/scripts/run_sim.sh; done` (저장소 루트)
- `tools/sim/sim_top.sh`는 **고치지 않았다** — 그대로 컴파일·실행되었고, 거르기 후 로그에 WARNING 0줄, ERROR 0줄.
- 커밋한 증거: `p01~p04/validation/xsim_rtl_20261123.log` (네 파일, 개인 경로 0건)

| 장 | 마지막 줄 | CASE_PASS (sort -u) xsim / Icarus | diff |
|---|---|---|---|
| p01 | `RTL_SIM_PASS stages=4` | 34 / 34 | 0줄 |
| p02 | `RTL_SIM_PASS stages=8` | 147 / 147 | 0줄 |
| p03 | `RTL_SIM_PASS stages=4` | 64 / 64 | 0줄 |
| p04 | `RTL_SIM_PASS stages=4` | 111 / 111 | 0줄 |

비교 대상 Icarus 로그는 main에 커밋된 `pNN/validation/rtl_sim_20261123.log`(웹 01:50Z 판) 그대로다. 비교 명령:
`diff <(grep CASE_PASS pNN/validation/rtl_sim_20261123.log | sort -u) <(grep CASE_PASS pNN/validation/xsim_rtl_20261123.log | sort -u)` — `rx="…"` 내용 포함 네 장 모두 차이 없음. p03은 `PYTHON_*` 기준 모델 줄도 두 로그가 같다.

합격 기준 충족. 장 페이지 실행 명령을 xsim 기준으로 바꿔도 된다.

## 2. 발견한 문제 (수정하지 않음 — 웹 담당 파일)

1. **판정이 Python 기준 모델 실패를 못 잡는다.** 처음에는 numpy가 없는 시스템 `python3`로 돌렸는데, p03에서 `p03/reference/p03_model.py`가 `ModuleNotFoundError: No module named 'numpy'`로 죽었다. 그래도 `RTL_SIM_PASS stages=4`가 찍혔다. 이유: TB는 커밋된 사례 파일을 읽고, `run_sim.sh` 판정 정규식 `FATAL|_FAIL|^ERROR`가 `Traceback`과 `...Error:`를 잡지 못한다. 제안: 판정에 `PYTHON_PNN_SELF_TEST_PASS` 줄이 있는지 검사하고, `Traceback`도 실패로 본다. (커밋한 로그는 numpy가 있는 python 3.12로 다시 돌린 것이며, Traceback 0건이다.)
2. **`.gitignore`에 없는 xsim 산출물** — 저장소 루트에 `xvlog.pb`, `xelab.pb`, `xvlog.log`가 생긴다 (`-nolog`를 줘도 `xvlog.log`가 생긴다). `xsim.dir/`, `*.jou`는 이미 무시된다. `*.pb`, `xvlog.log`, `xelab.log`, `xsim*.log`(단, `pNN/validation/xsim_rtl_*.log`는 예외), `*.wdb`를 `.gitignore`에 추가해 달라. 이번에는 지우고 커밋하지 않았다.

## 3. 다음

2단계(00~12장 서브젝트 단독 TB, `part03/` VS Code 판 TB)는 따로 지시를 기다린다. 보드 점검(B1~B26)은 사용자와 함께.

## 4. 지시 16 회신 (2026-11-23 오후)

### 16-1 장 Top xsim (15번 대체): PASS
- `vscode/xsim-stage1`을 main 550bb80 기준으로 맞추고, Vivado 환경에서 인자 없이 `bash pNN/scripts/run_sim.sh` → 네 장 모두 `# tool: Vivado Simulator v2024.2.0` 자동 선택, `RTL_SIM_PASS stages=4/8/4/4`.
- 사례 줄(CASE_PASS, sort -u) 34/147/64/111, main의 `rtl_sim_20261123.log`와 diff 0줄. Traceback 0건.
- 한 STAGE만: `bash p02/scripts/run_sim.sh 3` → `P02_TOP_RTL_SIM_PASS stage=3 cases=25 bytes=163`, `RTL_SIM_PASS stages=1` (xsim).
- `tools/sim/sim_top.sh` 수정 없음. `docs/PROJECT_STATUS.md`는 `build_projects.py`로 재생성(XSIM_RTL_PASS ✅) — PR #7 정적 검사 실패(PROJECT_GUIDE_OUT_OF_DATE) 해소.

### 16-2 part03 소스 주석 정리
- main에 있는 `part03/` 소스(.v .sv .svh .c .h .py .tcl .xdc .sh) 중 **155개 수정**, 주석·docstring만. 파일마다 주석을 뺀 코드가 바꾸기 전과 같음을 기계 검사(Python은 docstring 뺀 AST 비교도). `git diff -w --shortstat` = 155 files, 352(+)/352(−).
- 규칙: `(추가)`·`(변경)`·`안 A`·날짜 꼬리표 삭제 / 이력 서술은 지금 동작 설명으로 / 옛 장 번호 → 서브젝트 번호(14장 → 3-2, 17장 → 4-2, 21장 → 5-2, 28장 → 6-1 …) / `Icarus`·`협동 시뮬레이션` → `RTL`·`PC 시뮬레이션`.
- 그대로 둔 것: `제1부 11장`·`제2부 07장`(다른 부의 장), `표본 22장`(그림 개수).
- **문자열이라 건드리지 않은 것** (장 페이지에 보임): `part03/common/sw/` 헤더의 `#error "안 A: axi_intc_0 입력은 16개여야 한다 …"`, `ch30/synth/soc30_bd.tcl` check 메시지 `"21장 안 A SoC(…)에서 시작"`·`"(21장 안 A)"`, `ch27/scripts/run_all.sh`가 찍는 `# 27장 run_all 결과`, `ch22/reference/gen_model.py`가 만드는 헤더 주석. 바꿔도 되면 알려 달라(출력이 바뀐다).
- 웹 담당 파일에 남은 꼬리표(참고): `common/rtl/uart_rx.v`·`uart_tx.v`·`uart_core.v`·`uart_echo_controller.v`, `ch00/rtl/basys3_uart_echo_top.v`의 `(추가)`/`(변경)`, p02 페이지의 `(변경) 입력이 초기 0에서…` 한 줄.
- `ch27/validation/run_all_summary.md`(p05 페이지에 실림)의 "이미 안 A로 실행한 기록" 한 줄은 run_all이 다시 쓰는 파일이라 아직 그대로다.
- `LEVEL=sim bash part03/ch27/scripts/run_all.sh` (iverilog): `host_integer_reference` PASS, `rtl_ch13_26` PASS. 비트스트림 재빌드 없음.

### 16-3 BOARD_CHECKLIST
- B 항목의 절차·기대 결과 칸 11곳: `21장 비트스트림` → `5장 비트스트림`(CK_SUBS와 같은 표기), `(22장 협동 시뮬레이션과 같은 줄)`·`(안 A 22장 표시)`·`(협동 시뮬레이션 SHOW 줄)`·`(23장 SoC xsim 값)`·`rtl_cosim.csv`와 같은 … 꼬리표·`, 협동 시뮬레이션` 삭제, `25장 값은` → `5-6 전력 값은`, `28장 펌웨어는` → `이 펌웨어는`, `22장 scores_match` → `표본 22장 scores_match`(개수).
- 추가로 머리말·준비 줄의 `(변경)`·`(추가)`·`안 A`·날짜, 표 머리 `기대 결과 (협동 시뮬레이션 근거)` → `기대 결과`. 절 제목(`## 1-28. 28장 …`)의 장 번호는 사용자가 보드에서 쓰는 순서라 그대로. 생성기는 `| B` 줄만 읽으므로 영향 없음.

### 16-4 2단계: part03 RTL 단독 run_sim.sh xsim
- 새 공용 파일 `part03/common/scripts/p3_sim.sh` (`p3_sim_version`·`p3_sim_build`·`p3_sim_run`, 선택 규칙은 `tools/sim/sim_top.sh`와 같다: SIM → xvlog 있으면 xsim → iverilog). xsim은 출력 폴더 안에서 `xvlog -sv` → `xelab -generic_top` → `xsim -R -testplusarg`. `$fatal`은 종료 코드와 출력 둘 다로 실패 판정(+ACTUAL을 빼고 돌려 rc=1 확인).
- 13~20·26장 `run_sim.sh` 9개를 이 함수로 바꿨다. **9개 장 모두 xsim·iverilog 양쪽 PASS, PASS 줄(사이클 수·cases·errors_checked 포함) diff 0**. xsim 11~60 s(18장이 가장 김), iverilog 0~18 s.
- 참고: 13장 TB는 무작위 valid 간격이라 `$finish` 시각이 다르다(xsim 131600 ns, iverilog 91940 ns, `$urandom` 수열 차이). actual 파일은 비트 단위로 같다.
- C 펌웨어와 함께 도는 22·28~31장(PC 시뮬레이션: FIFO + vvp 프로세스)은 iverilog 그대로. xsim 방식은 시험 전 — 정해지면 회신한다.
- Vivado 환경 `LEVEL=sim run_all`(13~20·26장이 xsim으로 돎)은 실행 중 — 결과는 다음 회신.

## 5. 지시 17 회신

- 17-1 확인(main 05d6c6e 병합 뒤): `bash p01/scripts/run_sim.sh` → `# tool: Vivado Simulator v2024.2.0`, `RTL_SIM_PASS stages=4`. `bash p02/scripts/run_sim.sh 3` → 사례 줄 + `RTL_SIM_PASS stages=1`. 새 판정 시험: Traceback만 찍고 죽는 가짜 `python3`를 PATH 앞에 두면 RTL 줄이 PASS여도 `RTL_SIM_FAIL`, rc=1 — 의도대로.
- 17-2~17-4(= 16-2~16-4)는 4절 그대로이며 이 PR(`vscode/xsim-stage1` → main)에 들어 있다. 병합 충돌은 생성 HTML(p05) 한 곳뿐이었고 생성기로 다시 만들었다(`--check` 둘 다 UP_TO_DATE).
