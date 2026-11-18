# VS Code Claude 인계 — 코드·실행 담당

학습안내서(HTML)는 생성기가 만든다. VS Code Claude는 **코드·실행·증거·`chapter.json`**을 맡고, HTML을 직접 고치지 않는다.

## 1. 역할 분담

| 담당 | 하는 일 | 하지 않는 일 |
|---|---|---|
| VS Code Claude (Vivado 설치 PC) | RTL·TB·기준 모델·`run_sim.sh` 작성, 시뮬레이션·Vivado 실행, `validation/` 증거 저장, `chNN/chapter.json` 작성 | `chNN_*_vNN.html`·`index.html`·`docs/GUIDE_STATUS.md` 직접 수정 |
| 웹 Claude (안내서 관리) | 생성기(`tools/guide/`) 관리, 안내서 재생성·검토, 현황표 관리, 장 간 정합성 점검 | 실행하지 않은 결과를 PASS로 표시 |

## 2. 지금 할 일 — 00~12장 Vivado 게이트

```bash
source /tools/Xilinx/Vivado/<버전>/settings64.sh
bash tools/run_vivado_all.sh            # 마지막 줄: VIVADO_ALL_PASS (all)
python3 tools/guide/build_guides.py     # 증거를 읽어 배지·현황표 갱신
git add ch*/validation/vivado_* ch*_v*.html index.html course.json docs/GUIDE_STATUS.md
git commit -m "test: 00~12장 Vivado 합성·타이밍·타이밍 시뮬레이션 증거"
```

- 실패하면 `build/vivado/logs/*.log`의 첫 ERROR와 `SYNTH_TIMING_FAIL`·`TIMING_SIM_FAIL` 줄을 그대로 보고한다. 스크립트는 Vivado 없이 모의 실행으로만 시험했으므로 첫 실행에서 명령 옵션 오류가 날 수 있다.
- 증거 파일 이름은 바꾸지 않는다. 생성기가 아래 이름으로 찾는다.

| 증거 | 경로 | 게이트 |
|---|---|---|
| RTL 시뮬레이션 로그 | `chNN/validation/rtl_sim_YYYYMMDD.log` | HOST_MODEL · RTL_SIM |
| OOC 합성·타이밍 | `chNN/validation/vivado_ooc_YYYYMMDD.txt` | SYNTH_TIMING |
| 12장 구현·타이밍 시뮬레이션 | `ch12/validation/vivado_impl_timesim_YYYYMMDD.txt` | SYNTH_TIMING · TIMING_SIM |
| 보드 기록 | `chNN/validation/board_YYYYMMDD.md` (`BOARD_PASS` 문구 포함) | BOARD (현재 미실시) |

같은 종류가 여러 개면 날짜가 가장 늦은 파일을 쓴다. 로그에는 개인 경로를 넣지 않는다(`<repo>`로 치환).

## 3. 13~31장 새 장 추가 계약

한 장은 아래가 모두 있어야 안내서가 만들어진다.

```
chNN/
├── chapter.json          ← 안내서 내용의 단일 원본 (형식: tools/guide/chapter.template.json)
├── rtl/  tb/  reference/ ← 전체 코드 (안내서에 원문 그대로 실림)
├── scripts/run_sim.sh    ← 저장소 루트에서 실행, 실패 시 exit≠0, 통과 시 *_SIM_PASS 한 줄 이상
└── validation/rtl_sim_YYYYMMDD.log
```

- `run_sim.sh` 출력 규칙: 통과 줄은 `RTL_SIM_PASS …`(또는 `…_SIM_PASS`), Python 기준 모델은 `PYTHON_…_SELF_TEST_PASS`, 실패는 `$fatal` 또는 `…_FAIL`. 로그 첫 줄 근처에 `Icarus Verilog version …`이 찍히게 한다(`iverilog -V | head -1`).
- 이전 장 파일은 수정하지 않고 `keep`에 적는다. 이번 장에서 만든 파일만 `new`에 적는다. 모듈 출처(구조도의 "NN장 재사용")는 `new` 목록으로 자동 판정된다.
- `version`은 13~31장 `v02`. `top.file`·`top.module`은 실제 선언과 일치해야 한다(생성기가 포트를 파싱).
- `port_notes`: Top 모듈의 **모든 포트**에 한글 설명(실제 코드명 + 쉬운 설명, flowchart-rules 5절). 빠지면 생성 실패.
- `fsm`: Top 파일에 상태 `localparam`이 있으면 `case(state)` 기준 전이표를 쓴다. 상태명 불일치·누락은 생성 실패. 구조도는 상태 목록만 보여 주며 전이는 이 표가 담당한다.
- `run_note`: 실행 명령의 기능 설명(STANDARD 5.2).
- Vivado 대상이면 `vivado.mode`를 `ooc`로 하고 `tools/vivado/ooc_timing.tcl`의 `designs` 표에 한 줄을 추가한다. 보드 Top이면 `top`, 다른 장 Top에 포함되면 `via` + `ref`.
- 커밋 전에 반드시 실행한다:

```bash
python3 tools/guide/build_guides.py && python3 tools/guide/build_guides.py --check && python3 tools/check_static.py
```

화면을 바꿨거나 새 장을 넣었으면 화면 점검도 실행한다(Playwright 필요):

```bash
python3 tools/guide/audit_render.py      # → docs/RENDER_AUDIT.md, 마지막 줄 RENDER_AUDIT_PASS
```

CI는 `--check`가 실패하면(코드·증거와 안내서가 어긋나면) 빨간불이 된다.

## 4. 원칙

- 실행하지 않은 결과를 로그·`chapter.json`에 적지 않는다. 기대값은 "기대값"으로 표기한다.
- 원본 `Yuul-Jung/amd_soc_rtl`은 수정하지 않는다.
- 00~12장 RTL은 버그 수정·주석·파라미터화만 허용(AGENTS.md).
