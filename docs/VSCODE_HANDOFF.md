# VS Code Claude 인계 — 코드·실행 담당

학습안내서(HTML)는 생성기가 만든다. VS Code Claude는 **코드·실행·증거·`chapter.json`**을 맡고, HTML을 직접 고치지 않는다.

## 1. 역할 분담

| 담당 | 하는 일 | 하지 않는 일 |
|---|---|---|
| VS Code Claude (Vivado 설치 PC) | RTL·TB·기준 모델·`run_sim.sh` 작성, 시뮬레이션·Vivado 실행, `validation/` 증거 저장, `chNN/chapter.json` 작성 | `chNN_*_vNN.html`·`index.html`·`docs/GUIDE_STATUS.md` 직접 수정 |
| 웹 Claude (안내서 관리) | 생성기(`tools/guide/`) 관리, 안내서 재생성·검토, 현황표 관리, 장 간 정합성 점검 | 실행하지 않은 결과를 PASS로 표시 |

## 2. 지금 할 일 (2026-11-23 갱신)

00~12장 Vivado 게이트, 13~31장 VS Code 판(`part03/`) 빌드, 안 A 재빌드는 끝났다. 현재 지시는 **[docs/plan/VSCODE_DIRECTIVE_A.md](plan/VSCODE_DIRECTIVE_A.md)의 가장 큰 번호 항목**을 따른다 (지금은 17: part03 주석·점검표 문구 정리, part03 시뮬레이션의 Vivado 시뮬레이터 전환).

증거 파일 이름은 바꾸지 않는다. 생성기가 아래 이름으로 찾고, 같은 종류가 여러 개면 날짜가 가장 늦은 파일을 쓴다. 로그에는 개인 경로를 넣지 않는다(`<repo>`로 치환).

| 증거 | 경로 | 게이트 |
|---|---|---|
| RTL 시뮬레이션 로그 | `chNN/validation/rtl_sim_YYYYMMDD.log` · `pNN/validation/rtl_sim_YYYYMMDD.log` | HOST_MODEL · RTL_SIM |
| OOC 합성·타이밍 | `chNN/validation/vivado_ooc_YYYYMMDD.txt` (WNS=NA는 `SYNTH_TIMING_NOT_CHECKED`) | SYNTH_TIMING |
| 장 Top 구현 | `pNN/validation/vivado_impl_YYYYMMDD.txt` (STAGE마다 한 줄) | SYNTH_TIMING |
| 12장 구현·타이밍 시뮬레이션 | `ch12/validation/vivado_impl_timesim_YYYYMMDD.txt` | SYNTH_TIMING · TIMING_SIM |
| DRC REQP-1840 | `{ch12,pNN}/validation/drc_reqp1840_YYYYMMDD.txt` (`count=` 줄, 0이면 게이트 칸이 사라진다) | DRC |
| 보드 기록 | `chNN/validation/board_YYYYMMDD.md` (`BOARD_PASS` 문구 포함) | BOARD (현재 미실시) |

역할: Vivado·Vitis·보드 실행과 `part03/`는 VS Code, 생성기·안내서·`pNN/`·`mini_npu/`·`tools/`는 웹. 경계 밖 파일은 고치지 말고 `part03/ch27/docs/VSCODE_TO_WEB_*.md`로 요청한다.

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
- 상태도: `fsm.diagram`에 `chNN/diagrams/<이름>`(확장자 없음)을 쓰고, [svg-flow-editor](https://yuul-jung.github.io/svg-flow-editor/)에서 **작업 불러오기 → 편집 → 작업 저장**한 JSON을 그 경로에 둔 뒤 `python3 tools/diagram/export_svg.py`로 SVG를 만든다(편집기 품질 검사 0건일 때만 저장). 상태 노드 제목 = `localparam` 이름, 간선 = 전이표의 상태 간 전이(자기 유지·`default`·`(모든 상태)` 제외)여야 하며, 생성기가 대조한다. JSON을 고치고 SVG를 다시 만들지 않으면 생성이 실패한다.
- 00~12장 RTL의 모듈·인스턴스 관계를 바꾸면 `diagrams/module_techtree_00_12.json`도 편집기에서 같이 고쳐야 한다(모듈 노드·간선·×N을 생성기가 RTL과 대조). 13장 이후 테크트리는 해당 장 코드가 들어온 뒤 별도 도면으로 추가한다.
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
