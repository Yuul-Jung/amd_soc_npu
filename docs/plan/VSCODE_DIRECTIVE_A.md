# VS Code 지시문 — 제3부 SoC를 동결 주소맵(안 A)으로 (2026-11-19)

> VS Code에 붙여 넣을 한 줄:
> `git fetch origin && git show origin/restructure/projects:docs/plan/VSCODE_DIRECTIVE_A.md` 를 읽고 그대로 수행해 줘. 질문 없이 진행하고, 끝나면 7절 형식으로 보고해.

## 0. 결정 (웹 Claude·사용자 확정)

| 항목 | 결정 |
|---|---|
| 13~31장 코드 기준 | **VS Code 판 전체** (`vscode/part03-ch13-31`). 웹 판 13~31장 코드는 쓰지 않는다 |
| 5·6장 SoC 주소 | **동결 주소맵(안 A)** — 아래 2절 |
| 표시기 | 28장 `axi_gpio_1` + `p3_fnd_scan` 대신 표준 7세그먼트 IP `ip_seg7`(ID `SEG7`)을 **21장 SoC부터** 넣는다 |
| 28~31장 하드웨어 | 21장 비트스트림·XSA를 그대로 쓰고 ELF만 새로 만든다 (28장 BD 별도 빌드 폐지) |

## 1. 충돌을 막는 작업 경계

| 누가 | 브랜치 | 고치는 곳 |
|---|---|---|
| VS Code | `vscode/part03-ch13-31` (지금 브랜치 계속) | `part03/` 아래만 (예외: 3절 8번의 `p01`~`p04/validation/vivado_impl_*.txt` 네 파일은 `restructure/projects`에) |
| 웹 Claude | `restructure/projects` | `docs/`·`tools/guide/`·`AGENTS.md` (이 파일 포함) |

- `main`에는 둘 다 푸시하지 않는다. 원본 `Yuul-Jung/amd_soc_rtl`과 제1부 11장 원본 프로젝트는 고치지 않는다 (복제본만).
- 이 지시문과 `docs/plan/handoff/`는 읽기만 한다. 필요한 파일은 `part03/` 안으로 **복사**해서 쓴다.

## 2. 목표 주소맵 (MicroBlaze V Data 주소 공간)

| 인덱스 | 블록 | 베이스 | 범위 | 지금 (VS Code 21장) |
|---|---|---|---|---|
| — | LMB BRAM | 0x0000_0000 | 64 KB | 같음 |
| [00] | `axi_gpio_0` LED(16)/SW(16) | 0x4000_0000 | 64 KB | 같음 |
| [01] | `axi_gpio_btn` BTN 4비트 (btn[3]=U·[2]=D·[1]=L·[0]=R, 인터럽트 켬) | 0x4001_0000 | 64 KB | 없음 → **추가** (11장 BD에 이미 있으면 주소만) |
| [02] | `axi_uartlite_0` 115200 | 0x4002_0000 | 64 KB | 0x4060_0000 → **변경** |
| [03] | `axi_timer_0` | 0x4003_0000 | 64 KB | 0x41C0_0000 → **변경** |
| [04] | `axi_intc_0` | 0x4004_0000 | 64 KB | 0x4120_0000 → **변경** |
| [05] | IIC | 0x4005_0000 | — | 넣지 않음 (자리만 비움) |
| [06] | `ip06_seg7` = `ip_seg7` 1.0 | 0x4006_0000 | 64 KB | 없음 → **추가** |
| — | `p3_npu_0` | 0x44A0_0000 | 4 KB | 같음 |

인터럽트: `xlconcat` 입력 **16개**로 바꾼다. 쓰지 않는 입력은 상수 0.

| INTC 입력 | 연결 | 지금 |
|---|---|---|
| In0 | `axi_timer_0/interrupt` | 같음 |
| In1 | `axi_uartlite_0/interrupt` (예약 — 연결은 하되 펌웨어는 켜지 않음) | NPU → **변경** |
| In2 | 0 (IIC 예약) | — |
| In3 | `axi_gpio_btn/ip2intc_irpt` | — |
| In4~In11 | 0 (C 시리즈 확장 블록 예약, `soc_map.h`) | — |
| **In12** | `p3_npu_0/irq_o` (C00 예약칸 In12~In14의 첫 칸) | In1 |
| In13~In15 | 0 | — |

## 3. 할 일 (순서대로, 단계마다 원자 커밋)

1. **미커밋 정리 먼저.** 27~29장 미커밋 8개, `common/sw`, 30·31장을 장 단위 원자 커밋으로 올리고 푸시한다. 30장 비트스트림·28장 xsim 미완료는 그대로 `NOT_RUN`으로 둔다(2절 작업 뒤 다시 만든다).
2. **SEG7 IP 가져오기.** `docs/plan/handoff/ip_seg7/` 세 파일(`ip_seg7.v`, `axil_slave.v`, `ip_std.v`)을 `part03/common/rtl/ip_std/`로 복사한다. 내용은 고치지 않는다. 짧은 Icarus TB로 VALUE·MODE·RAW 쓰기/읽기와 0xFFF0 ID = 0x53454737을 확인하고 로그를 남긴다.
3. **21장 BD 변경** (`ch21/synth/soc_npu_bd.tcl`, 복제 프로젝트에서만): 2절 표대로 주소 변경·BTN GPIO·SEG7(모듈 참조 또는 IP 패키징, 쉬운 쪽)·concat 16입력. 사용자 Top에 `seg[6:0]`·`dp`·`an[3:0]`·`btn[3:0]` 포트를 핀 연결만으로 추가 (Top은 배선만, MBV_SOC §4). 핀은 Basys-3-Master.xdc 그대로.
4. **검사 스크립트 강화** (`ch21/scripts/check_bd.tcl` 또는 같은 역할): Address Editor 값을 2절 표와 한 줄씩 대조해 `ADDR_MAP_A_PASS`/`FAIL`, INTC 입력 번호를 대조해 `IRQ_MAP_A_PASS`/`FAIL`을 찍는다. 겹침 없음 검사는 그대로.
5. **21장 재빌드**: `scripts/build_soc.sh` → 비트스트림·XSA. `validation/soc_summary.md`를 새 값(주소 표, WNS·WHS, LUT·FF·BRAM·DSP, SHA-256)으로 다시 쓴다. 이전 값은 Git 이력에만 남긴다.
6. **펌웨어**: 22장부터 주소는 `xparameters.h`만 쓴다(하드코딩 금지). `rg -n '0x4060|0x41C0|0x4120|0x4001' part03`이 BD 검사 기대값 외에는 0건이어야 한다. NPU 인터럽트를 쓰는 코드는 INTC 비트 12로. 22장 드라이버에 표시 코드를 추가한다: 추론 뒤 클래스를 LED 한 개 + 7세그먼트 오른쪽 자리(VALUE), 왼쪽 두 자리는 그림 번호.
7. **다시 돌릴 것**: 22 ELF → 23 SoC 시뮬(CPU·NPU 클록 값 갱신) → 25 report_power(같은 SAIF 절차) → 27 `run_all` (`LEVEL=sim`과 가능하면 `LEVEL=vivado`) → 28 ELF(21장 XSA로 플랫폼, `basys3_soc28_top`·`soc28_bd.tcl`·`axi_gpio_1`·`p3_fnd_scan`은 삭제하고 `p3_fnd_scan`은 RTL 시험용으로만 남길지 판단해 보고) → 29·30·31 ELF + `ELF_MEM_PASS`. 24장 OOC 스윕은 주소와 무관하므로 다시 돌리지 않는다.
8. **(1장 시범, 위 작업 뒤)** 웹이 만든 1장 Top의 Vivado 실행: `git worktree add ../npu_restructure origin/restructure/projects` → 그 폴더에서 `vivado -mode batch -nojournal -source p01/vivado/build_p01.tcl` (1장 STAGE 1~4), `p02/vivado/build_p02.tcl` (2장 STAGE 1~8), `p03/vivado/build_p03.tcl`, `p04/vivado/build_p04.tcl` (3·4장 STAGE 1~4). 생기는 `p01`~`p04/validation/vivado_impl_YYYYMMDD.txt` **네 파일만** `restructure/projects`에 커밋·푸시한다. 다른 파일은 고치지 않는다. 실패하면 결과 그대로 보고.
8-1. ✅ 완료 (7eb69ed, WNS +0.484). **(2장 STAGE 8 재실행)** 웹이 12장 `mini_npu/rtl/npu_engine4.v`의 argmax를 두 클록 토너먼트로 고쳤다 (임계 경로 `u_e4/lane1/acc_o_reg → class_o_reg`, WNS −1.952 ns 대응, 00~12장 회귀·적대 시험 PASS, 2장 Top 8단계 PASS). `restructure/projects`를 받아 `vivado -mode batch -nojournal -source p02/vivado/build_p02.tcl -tclargs 8`을 다시 돌리고, 결과 줄을 `p02/validation/vivado_impl_YYYYMMDD.txt`에 추가해 커밋한다 (STAGE 1~7 줄은 그대로 둔다).
8-2. ✅ 완료 (c32d094, CPU 4.596 · NPU 2.765 mJ). **(25장 전력 재실행)** `part03/ch25/validation/power_summary.md`는 2026-11-18(안 A 이전) 21장 SoC 기준이다. 안 A 비트스트림으로 `bash part03/ch25/scripts/run_power.sh`를 다시 돌려 `power.log`·`power_summary.md`를 갱신하고 커밋한다 (5장 페이지 5-6이 ⚠로 표시 중).
9. **보드 점검표** `ch27/docs/BOARD_CHECKLIST.md`: 비트스트림·XSA·ELF SHA를 새 값으로, 7세그먼트·BTN 항목을 서브젝트마다 하나 이상 넣는다. 모두 `NOT_RUN` 유지.
10. ✅ 완료 (e0cae5c 28장 xsim 15/15 · 336d1b2 30장 재빌드). **(6장, 웹 결정 2026-11-19)** 6장 페이지가 ⚠로 표시 중인 두 가지.
   - **28장 안 A SoC xsim**: `ch28/validation/soc_sim_mapA_20261119.log`가 프레임 송신 중에 끝나 판정 줄이 없다. `bash part03/ch28/scripts/run_soc_sim.sh`를 끝까지 돌려 `SOC28_RTL_SIM_PASS checks=…`를 남긴다 (시간 제한이 원인이면 제한만 늘린다).
   - **30장 SoC 안 A 재빌드**: 30장은 핀(JB Pmod·`estop_ok`)과 `p3_motor_safety` RTL이 필요해 ELF만으로는 안 된다(판단 결과: 별도 비트스트림 유지). 21장 블록 설계(안 A 그대로) + `p3_motor_safety_bd`를 **0x4007_0000**(빈 칸, 64 KB)에 붙이고, 인터럽트를 쓰면 **In4**(C 시리즈 확장 예약 첫 칸)로. 다른 주소·인터럽트는 바꾸지 않는다. 검사: `ADDR_MAP_A_PASS`(21장 8줄 + 모터 1줄), 안전 코어 핀 XDC, WNS·WHS ≥ 0. 펌웨어 모터 주소는 `xparameters.h`만. 점검표 B18~B23a 기대값·SHA를 새 빌드로 갱신 (모두 NOT_RUN 유지).

## 4. 지킬 것

- 웹 쪽 `restructure/projects`는 3장용으로 VS Code 판 `part03/ch13~19`·`part03/ch04/rtl/bram_sync_buffer.v`·`part03/host_tools`·`part03/ch02/rtl/dsp_multiplier.v`·`part03/mini_npu/rtl/npu_dsp_mac_lane.v`를 커밋 `9203bfa` 그대로 가져갔다 (`docs/plan/part03_snapshot.md`). 이 파일들을 고치면 보고서에 적는다 (웹이 다시 가져온다).

- 실행하지 않은 것은 `NOT_RUN`/`⚠ 미검증`. 추정값(전력)은 추정이라 적는다.
- 로그에는 개인 경로를 `<repo>`로 바꿔 넣는다. 토큰·계정 정보 금지.
- 커밋 끝 줄은 지금까지와 같은 Co-Authored-By 형식.
- 타이밍을 못 맞추면(WNS < 0) 억지로 고치지 말고 결과 그대로 보고한다.

11-1. **(12장 타이밍 시뮬레이션 단축, 웹 2026-11-20)** `run_timing_sim.sh` 기본이 짧은 시나리오(`+SHORT`)가 됐다: 분류 1 · Bias 변경 뒤 재분류 1 · ERR 1. 같은 넷리스트·SDF·UART 핀 경로이고 응답 수만 6 → 2 (Icarus 기능 시뮬 기준 시뮬 시간 29.2 → 10.8 ms, 2.7배 단축 — 시간은 대부분 115200 bps 송신). 판정 줄 `TIMING_SIM_PASS … classes=2 … scenario=short`. 지금 도는 전체 실행이 `TIMESIM_PROGRESS`로 응답 수가 늘고 있으면 그대로 두고, 멈춰 있거나 다시 돌려야 하면 짧은 시나리오로 실행한다. 전체는 `TIMESIM_FULL=1`.
11-3. **(2026-11-22 밤, VSCODE_TO_WEB_20261122 회신)**
   - 1절 반영: `tb_npu_uart.sv`의 `edit_idx` 선언을 함수 앞으로 옮김 (xvlog VRFC 10-3380). 웹은 xvlog가 없어 Icarus로만 확인 — xvlog·xelab 통과는 VS Code에서 확인 바람.
   - 3절 반영(11-1 철회): `run_timing_sim.sh` 기본은 **전체 시나리오** → `TIMING_SIM_PASS`. 짧은 것은 `TIMESIM_SHORT=1` smoke → `TIMING_SIM_SMOKE_PASS`(게이트 증거 아님). LED1·2 변이를 smoke가 놓치는 것을 웹에서도 재현함. 판정 줄에 `timing_violations=<수>` 추가 (xsim 경고 문구 "Timing violation" 기준, 실제 문구는 로그로 확인 바람).
   - 2절 반영: `ooc_timing.tcl`은 NA를 `SYNTH_TIMING_NOT_CHECKED`로 출력, 생성기는 `WNS=NA`를 ⚠ 미검사로 표시(01·02·04장). 장 페이지 서브젝트는 장 Top STAGE 배선 결과로 판정.
   - 4절 REQP-1840: 저장소에 증거 파일이 없어 웹은 아직 페이지에 쓰지 않았다. DRC 보고서 발췌(REQP-1840 줄, 대상 셀)를 `ch12/validation/`·`p02~p04/validation/`에 커밋해 주면 페이지에 미해결로 표시한다. RTL 변경(동기 리셋)은 사용자 승인 대기.
   - 6절: `timesim_sanitize.py`·`run_timing_sim.sh` 수정은 유지. `ooc_timing.tcl`의 빈 SLACK→NA 변경도 유지(판정만 위처럼 바꿈).
   - 7절: 12장 SDF 전체 시나리오는 이 커밋으로 다시 실행해도 되고, `47c2f79` 사본 결과를 올려도 된다(설계·넷리스트가 같음을 증거에 적을 것).
11-2. **(2026-11-22)** 구 11장·13~16장 단독 OOC는 돌리지 않아도 된다. 2장 2-7·2-8과 3장 서브젝트의 Vivado 게이트는 장 Top STAGE n 배선 결과로 판정하도록 생성기를 바꿨다. VS Code에 남은 Vivado 작업은 12장 SDF 시뮬레이션(11-1) 하나다.
11. **(남은 것, 2026-11-20)** 12장 배선 후 SDF 타이밍 시뮬레이션이 끝나면 `ch12/validation/vivado_impl_timesim_20261120.txt`를 `restructure/projects`에 커밋 (2장 2-8 TIMING_SIM 게이트가 대기 중). 웹 판 `ch26`·`ch29` OOC FAIL은 고치지 않는다 (개편 장은 `part03` VS Code 판을 쓴다).

12. **(REQP-1840 수정 재빌드, 사용자 승인 2026-11-22)** 브랜치 `fix/sync-reset`에 리셋 모듈 두 개를 동기 리셋으로 바꿨다 (`mini_npu/rtl/npu_reset_controller.v`, `p01/rtl/p01_reset_sync.v` — btnC 2단 동기화, 비동기 clear 없음. 다른 RTL·XDC는 그대로).
    - 웹 확인: 00~12장 회귀·adversarial·1~4장 Top 시뮬레이션 PASS, 리셋 단위 시험 `p01/tb/tb_p01_reset_sync.sv` PASS (이전 코드는 FAIL).
    - VS Code 할 일 (그 브랜치에서): ① p01~p04 전 STAGE `build_pNN.tcl` 재빌드 → `pNN/validation/vivado_impl_YYYYMMDD.txt` ② 12장 `vivado_impl.tcl` + `run_timing_sim.sh`(전체) ③ 각 빌드의 `report_drc`에서 REQP-1840 건수 → `drc_reqp1840_YYYYMMDD.txt` (0건이면 `count=0`으로 기록) ④ 타이밍이 나빠지면(리셋 fanout) 수치와 함께 보고. 증거만 `fix/sync-reset`에 커밋.
    - 통과하면 웹이 `fix/sync-reset`을 main에 병합한다. 그 전까지 main의 2~4장·12장 페이지는 REQP-1840 ⚠ 미해결 표시를 유지한다.

13. **(2026-11-23 00:50, 지시 12 중간 회신에 대한 결정 — 지금 실행할 것은 이 항목이다)**

    **결정**: 2장 STAGE 8은 구현 옵션이 아니라 **RTL 레지스터 한 단**으로 고쳤다 (`fix/sync-reset` d826c0b, `p02/rtl/p02_npu_path.v`). 고른 엔진의 done·error·class·scores를 레지스터에 받아 11장 해석기로 넘긴다. 응답 1클록 지연, 값 동일. 웹 확인: p02 Top STAGE 1~8 시뮬레이션 PASS, 클래스 선택 변이를 TB가 잡음. 구현 옵션(Explore)은 쓰지 않는다 — `build_p02.tcl`은 그대로.

    **실행 순서** (브랜치 `fix/sync-reset`, 이 PC에서는 원격 이름 `npu`):
    ```bash
    git fetch npu && git checkout fix/sync-reset && git pull --ff-only npu fix/sync-reset   # faf242d 이상
    # ① 2장만 전 STAGE 재빌드 (RTL이 바뀐 것은 p02_npu_path.v 하나 — p01·p03·p04·12장은 9e95d4d 결과 유지)
    for n in 1 2 3 4 5 6 7 8; do vivado -mode batch -nojournal -source p02/vivado/build_p02.tcl -tclargs $n; done
    # ② 12장 SDF 전체 시나리오가 아직 안 끝났으면 끝까지 (동기 리셋 넷리스트 기준)
    bash mini_npu/scripts/run_timing_sim.sh
    ```
    **남길 증거** (모두 `fix/sync-reset`에 커밋·푸시, 개인 경로는 `<repo>`):
    - `p02/validation/vivado_impl_YYYYMMDD.txt` — STAGE 1~8 여덟 줄 (오늘 날짜 새 파일. FAIL 줄이 있으면 그대로 남긴다)
    - `p02/validation/drc_reqp1840_YYYYMMDD.txt` — 새 빌드 8개의 `count=` 줄
    - `ch12/validation/vivado_impl_timesim_YYYYMMDD.txt` — 동기 리셋 넷리스트의 `SYNTH_TIMING_PASS` 줄 + `TIMING_SIM_PASS … timing_violations=0 scenario=full`
    - 증거를 올린 뒤 `python3 tools/guide/build_guides.py && python3 tools/guide/build_projects.py`는 **돌리지 않아도 된다** (웹이 재생성한다). 돌렸다면 결과 HTML도 같이 커밋한다 — 증거만 올리고 HTML을 빼면 CI `--check`가 실패한다는 점만 알아 둔다.

    **합격 기준** (전부 만족해야 웹이 main에 병합한다):
    | 조건 | 기준 |
    |---|---|
    | p01~p04 전 STAGE (20개) | 모두 `SYNTH_TIMING_PASS` (WNS ≥ 0, WHS ≥ 0, DRC_ERRORS=0) |
    | REQP-1840 | 21개 빌드 모두 0건 (p02는 새 빌드 기준) |
    | 12장 | 구현 PASS + SDF 전체 시나리오 PASS, timing_violations=0 |
    | 동작 중 btnC 시험 | 0건 유지 (`reset_press_timesim_*.txt`, 이미 확인됨 — 12장 RTL은 안 바뀌었으므로 재실행 불필요) |

    **실패했을 때**: 고치지 말고 보고한다 — 실패 STAGE, WNS/WHS, 최악 경로의 Source·Destination·Logic Levels·Data Path Delay(`report_timing` 발췌)를 `part03/ch27/docs/VSCODE_TO_WEB_YYYYMMDD.md`에 적는다. `pNN/rtl`·`mini_npu/rtl`·`tools/`·`*.tcl`은 웹 담당이므로 수정하지 않는다 (진단용 임시 Tcl은 커밋하지 않는다).

    **회신 반영 (VSCODE_TO_WEB 9절)**: ① PROJECT_PLAN In4→In12 정정 ② GUIDE_STATUS에 "13~31장 줄은 웹 판 RTL 기준" 명시 ③ CI를 `restructure/projects`·`fix/**` push에서도 실행 ④ PROJECT_PLAN 8절·VSCODE_HANDOFF 2절 갱신 ⑤ main 공개 완료 (PR #1·#2, 2026-11-23 00:3x, CI 통과). 로컬 CI 예행연습은 **python3.11**로 돌릴 것 (웹도 같은 실수를 했다).

14. **(2026-11-23 04:1x, 지시 12·13 종료)** 합격 기준 충족 확인(1b99bd2·411b02c): 웹이 재생성·CI 확인 뒤 `fix/sync-reset`을 main에 병합했다. **지금 VS Code에 남은 지시는 없다.** 다음은 사용자와 함께 하는 실물 보드 점검(`part03/ch27/docs/BOARD_CHECKLIST.md` B1~B26, 1~4장 서브젝트별 보드 확인)뿐이다.
    - btnC 시험의 `timing_violations=16`(동기화 첫 단 `sync_q[0]`)은 비동기 입력을 받는 플립플롭의 예상된 경고로 받아들인다. 합격 기준 "0건"은 RAMB18 위반 수가 맞다.
    - 정정: 장 Top 전 STAGE 빌드는 인자 없이 `vivado -mode batch -nojournal -source pNN/vivado/build_pNN.tcl` **한 번** (STAGE마다 따로 돌리면 증거 파일이 덮어써진다). 지시 13 ①의 반복문은 틀렸다.
    - 다음 재빌드가 필요해지면 15번으로 적는다.

15. **(2026-11-23 11:00, Vivado 시뮬레이터로 RTL 시뮬레이션 확인 — 실행 명령은 16번 1로 바뀌었다)**

    **배경**: 실습하는 사람은 Vivado에서 시뮬레이션한다. 지금 RTL 시뮬레이션 근거는 Icarus Verilog뿐이라 같은 과정을 두 번 거치게 된다. 같은 TB·사례 파일·판정 줄을 Vivado 시뮬레이터(xsim)로 돌려 증거를 남기고, 통과하면 장 페이지의 실행 명령을 xsim 기준으로 바꾼다. Icarus는 GitHub CI(Vivado 없음)용 자동 검사로 남긴다.

    **1단계 — 1~4장 장 Top** (main `git pull` 뒤, 저장소 루트에서):
    ```bash
    for p in p01 p02 p03 p04; do SIM=xsim bash $p/scripts/run_sim.sh; done
    ```
    - 실행기는 `tools/sim/sim_top.sh` (`xvlog -sv` → `xelab -generic_top STAGE=n` → `xsim -R`). **웹은 xsim을 돌려 보지 못했다(⚠ 미검증)** — 옵션·출력 거르기가 틀렸으면 **이 파일 하나는 VS Code가 고쳐도 된다** (xsim 분기만, Icarus 분기는 그대로).
    - 증거: `pNN/validation/xsim_rtl_YYYYMMDD.log` (스크립트가 만든다. 첫 줄들에 `# tool: Vivado Simulator …`, 마지막에 `RTL_SIM_PASS stages=N`). 네 파일을 main에 커밋(브랜치 → PR도 좋다). 개인 경로는 스크립트가 `<repo>`로 바꾼다.
    - `xsim.dir/`·`*.jou`·`*.pb`·`*.wdb`는 커밋하지 않는다 (`.gitignore`에 없는 산출물이 생기면 알려 달라).

    **합격 기준**: 네 장 모두 `RTL_SIM_PASS stages=N`(4·8·4·4)이고, `PNN_CASE_PASS` 줄의 수와 `rx="…"` 내용이 같은 날짜 Icarus 로그(`rtl_sim_*.log`)와 같다 — `diff <(grep CASE_PASS p02/validation/rtl_sim_*.log | sort -u) <(grep CASE_PASS p02/validation/xsim_rtl_*.log | sort -u)` 형태로 확인하고 결과를 회신에 적는다.

    **xsim에서 컴파일·실행이 안 되면**: TB·RTL은 고치지 말고 보고한다 — 파일·줄·xvlog/xelab 메시지(VRFC 번호)를 `part03/ch27/docs/VSCODE_TO_WEB_YYYYMMDD.md`에. 웹이 고쳐 다시 지시한다 (12장 TB의 VRFC 10-3380과 같은 종류가 더 있을 수 있다).

    **2단계 (1단계 통과 뒤, 따로 지시)**: 00~12장 서브젝트 단독 TB, `part03/` VS Code 판 TB(이쪽은 VS Code 담당이므로 `run_sim.sh`에 같은 `SIM=xsim` 분기를 직접 넣는다 — `tools/sim/sim_top.sh`를 써도 된다). C 협동 시뮬레이션(22·28~31장)은 방식이 달라 마지막에 검토.

16. **(2026-11-23 12:30, 사용자 지시: 학습안내서에는 지금의 과정만 — 15번과 함께 실행)**

    **바뀐 것 (웹, main)**: 장 페이지에서 검증 표시·옛 장 번호·진행 위치 막대·Icarus 표기를 모두 뺐다. 옛 장 안내서 `chNN_*.html` 32개는 삭제했고 INDEX는 1~6장만 안내한다. 1~4장 `run_sim.sh`는 **Vivado가 있으면 Vivado 시뮬레이터(xsim), 없으면 iverilog**를 스스로 고르고, 숫자 인자를 주면 그 STAGE만 돈다 (`bash p01/scripts/run_sim.sh 2`). 장 페이지의 시뮬레이션 절은 이 명령과 기대 출력을 싣는다.

    **VS Code 할 일**
    1. (15번 대체) Vivado 환경에서 `for p in p01 p02 p03 p04; do bash $p/scripts/run_sim.sh; done` → 자동으로 xsim이 선택된다(`# tool:` 줄로 확인). `pNN/validation/xsim_rtl_YYYYMMDD.log` 네 개를 커밋한다. 한 STAGE만 도는 `bash p02/scripts/run_sim.sh 3`도 xsim에서 되는지 확인한다. **xsim 분기는 웹에서 한 번도 실행하지 못했다** — 옵션·출력 거르기가 틀리면 `tools/sim/sim_top.sh`의 xsim 분기는 고쳐도 된다. TB·RTL 오류면 고치지 말고 파일·줄·메시지를 회신한다. 합격 기준은 15번과 같다(사례 줄이 iverilog 로그와 같음).
    2. `part03/` 소스 주석 정리 (VS Code 담당 파일이라 웹은 손대지 않았다): 장 페이지에 그대로 실리는 `.v`·`.sv`·`.c`·`.h`·`.py`·`.tcl`·`.xdc`·`.sh`의 주석에서 ① `(추가)`·`(변경)`·`(변경) 안 A`·날짜 꼬리표 ② '이전에는/기존에는' 같은 이력 서술 ③ 옛 장 번호(`20장`·`22장`…) — 서브젝트 번호(5-1…6-5)나 모듈 이름으로 ④ `Icarus`·`iverilog`·`협동 시뮬레이션` 도구 이름을 뺀다. **주석만** 바꾸고 코드·문자열·출력 형식은 건드리지 않는다. 바꾼 뒤 `LEVEL=sim bash part03/ch27/scripts/run_all.sh` PASS를 확인하고 커밋한다 (비트스트림 재빌드는 필요 없다 — 주석만 바뀜을 `git diff -w --stat`와 함께 회신).
    3. `part03/ch27/docs/BOARD_CHECKLIST.md`의 절차·기대 결과 칸에서 `21장 비트스트림`·`(22장 협동 시뮬레이션과 같은 줄)` 같은 옛 장 번호·출처 꼬리표를 뺀다 (지금은 웹 생성기가 표시할 때 걸러 낸다 — `tools/guide/build_projects.py`의 `CK_SUBS`).
    4. 2단계: `part03/chNN/scripts/run_sim.sh`(13~20·26장 등 RTL 단독)도 Vivado가 있으면 xsim으로 돌게 한다 (`source tools/sim/sim_top.sh`의 `sim_kind` 사용 가능). C 펌웨어와 함께 도는 22·28~31장은 방식이 정해지면 회신한다.

    **회신**: `part03/ch27/docs/VSCODE_TO_WEB_YYYYMMDD.md`에 xsim 결과(통과/오류 메시지), 주석 정리한 파일 수, run_all 결과.

17. **(2026-11-23 16:00, VSCODE_TO_WEB_20261123 회신 반영 — 지금 실행할 것은 이 항목이다)**

    **받은 것**: 1~4장 장 Top xsim PASS (PR #7 병합, ae36318). 웹에서도 사례 줄 diff 0을 다시 확인했다. 16번 1항은 이것으로 끝.
    **반영한 것**: ① `run_sim.sh` 판정이 기준 모델 실패를 잡는다 — `PYTHON_PNN_SELF_TEST_PASS` 줄이 없거나 `Traceback`이 있으면 `RTL_SIM_FAIL` (python이 죽는 가짜 환경으로 확인) ② `.gitignore`에 `*.pb`·`*.wdb`·`xvlog.log`·`xelab.log`·`xsim*.log` 추가 (`pNN/validation/xsim_rtl_*.log`는 예외).

    **VS Code 할 일** (main `git pull` 뒤)
    1. 확인만: Vivado 환경에서 인자 없이 `bash p01/scripts/run_sim.sh`가 자동으로 xsim을 고르는지(`# tool: Vivado Simulator`), 한 STAGE만 도는 `bash p02/scripts/run_sim.sh 3`이 사례 줄과 `RTL_SIM_PASS stages=1`을 내는지. 증거 파일은 새로 올리지 않아도 된다(같은 날짜 파일이 이미 있다). 안 되면 메시지만 회신.
    2. 16번 2항 — `part03/` 소스 주석 정리 (이력 꼬리표·옛 장 번호·도구 이름·`안 A`). 장 페이지 코드 상자에 약 470곳이 그대로 보인다. 주석만 바꾸고 `LEVEL=sim bash part03/ch27/scripts/run_all.sh` PASS 확인.
    3. 16번 3항 — `BOARD_CHECKLIST.md`의 절차·기대 결과 칸 문구 정리.
    4. 16번 4항 — `part03/chNN/scripts/run_sim.sh`도 Vivado가 있으면 xsim으로 (`tools/sim/sim_top.sh`의 `sim_kind`·`sim_top` 사용 가능. TB가 `-P` 파라미터를 쓰지 않으면 `-generic_top` 줄만 빼고 같은 흐름). 통과 로그는 `part03/chNN/validation/xsim_rtl_YYYYMMDD.log`.
    5. `part03/` 변경은 평소처럼 `vscode/…` 브랜치 → main PR. 웹이 재생성·CI 확인 뒤 병합한다.

## 5. 웹 Claude가 그동안 하는 것

1장(구 00~03장) 시범 전환: 생성기를 "장 페이지 + 서브젝트 절" 구조로 바꾸고 미리보기를 만든다. VS Code 작업과 파일이 겹치지 않는다.

## 6. 판단이 필요하면

추측하지 말고 보고서의 "판단 필요" 칸에 적고 다음 항목으로 넘어간다 (예: 11장 BD에 BTN GPIO가 이미 다른 주소로 있는 경우, SEG7을 모듈 참조로 넣을 수 없는 경우).

## 7. 보고 형식

| 항목 | 결과 (PASS/FAIL/NOT_RUN) | 증거 파일 | 값 |
|---|---|---|---|
| 미커밋 정리 | | 커밋 해시 | |
| SEG7 TB | | | ID 읽기값 |
| ADDR_MAP_A / IRQ_MAP_A | | | |
| 21장 비트스트림 | | `soc_summary.md` | WNS·WHS·LUT·SHA |
| 22~31장 ELF | | | 크기·스택 끝 |
| 23장 클록 | | | CPU·NPU |
| 25장 전력 (안 A 재실행, 8-2) | | | CPU·NPU mJ |
| 27장 run_all | | | |
| 1장 Top STAGE 1~4 | | `p01/validation/vivado_impl_*.txt` | WNS·WHS·LUT·DSP |
| 2장 Top STAGE 1~8 | | `p02/validation/vivado_impl_*.txt` | WNS·WHS·LUT·DSP·RAMB18 |
| 3장 Top STAGE 1~4 | | `p03/validation/vivado_impl_*.txt` | WNS·WHS·LUT·DSP·RAMB18 |
| 4장 Top STAGE 1~4 | | `p04/validation/vivado_impl_*.txt` | WNS·WHS·LUT·DSP·RAMB18 |
| 28장 안 A SoC xsim (10) | | `soc_sim_mapA_*.log` | checks |
| 30장 안 A SoC (10) | | `build_soc_*.log` | 모터 주소·WNS·WHS·SHA |
| 판단 필요 | | | |

마지막 커밋 해시와 브랜치 이름을 적는다.
