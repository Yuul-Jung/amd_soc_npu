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
