# VS Code → 웹 Claude 전달 (2026-11-22)

대상은 `restructure/projects`(기준 `fd65a88`)이다. 아래 파일은 웹 담당이라 VS Code에서 고치지 않았다.

## 요청 요약

| 순위 | 요청 | 파일 |
|---|---|---|
| 1 | xvlog 컴파일 오류 수정 (1절) | `mini_npu/tb/tb_npu_uart.sv` |
| 2 | 경로 없음(NA)을 PASS로 세지 않기 (2절) | `tools/vivado/ooc_timing.tcl`, 01·02·04장 안내서, `docs/GUIDE_STATUS.md` |
| 3 | 타이밍 시뮬레이션 기본을 전체로 복귀 (3절) | `mini_npu/scripts/run_timing_sim.sh`, 지시 11-1 |
| 4 | BRAM 비동기 리셋 경고를 미해결로 표시 (4절) | 2~4장 페이지, 12장 안내서 |
| 5 | 26·29장 판정 기준 정리 (5절) | 안내서 생성기 |
| 6 | 경계 밖 수정 2건 검토 (6절) | 아래 |

## 1. `413b352`의 TB가 Vivado에서 컴파일되지 않는다

`ERROR: [VRFC 10-3380] identifier 'edit_idx' is used before its declaration` (`tb_npu_uart.sv:47`).
Icarus는 통과하지만 xvlog는 거부하므로 단축·전체 타이밍 시뮬레이션 모두 시작되지 않는다.

수정안: `integer edit_idx=5;` 한 줄을 79행 부근에서 `hexchar` 함수 앞으로 옮긴다.

```diff
     endtask
+    integer edit_idx=5;
     function automatic [7:0] hexchar(input [3:0] value);
...
     reg short_mode=1'b0;
-    integer edit_idx=5;
     reg signed [40:0] exp_score;
```

사본에서 확인: xvlog 통과, Icarus 전체 6회·단축 2회 PASS. xelab과 SDF 시뮬레이션은 이 수정안으로 실행하지 않았다.

## 2. 01·02·04장 OOC PASS는 잘못이다

세 장은 `WNS=NA WHS=NA`, setup·hold endpoint 없음이다. 판정식 `($wns eq "NA" || $wns >= 0)`이 PASS로 처리한다.
VS Code의 `200eedc`가 빈 SLACK을 NA로 바꾸면서 드러나지 않게 됐다. 올바른 집계는 **19 PASS · 2 FAIL · 3 미검사**(24개)이다.

- NA는 `SYNTH_TIMING_NOT_CHECKED`로 출력하고 PASS 집계와 ✅에서 뺀다.
- 실제로 검사하려면 앞뒤 레지스터 래퍼나 input/output delay 제약이 필요하다.

## 3. 단축 시나리오(11-1)는 결함을 놓친다

`led_o[3:0]=onehot&4'b1001`(LED1·2 고장) 변이를 Icarus로 실행하면 단축은 PASS, 전체는 `LED class mismatch` FAIL이다.
단축은 클래스 1·2를 만들지 않는다. 전체를 기본으로 하고 단축은 smoke 시험으로 구분해야 한다.
또 스크립트는 `Timing violation` 경고가 있어도 PASS를 출력하므로 경고 수를 판정 줄에 함께 남겨야 한다.

## 4. REQP-1840 (RAMB18 async control check)

12장 20건(보고 한도 도달), p02 STAGE 1~8, p03·p04 STAGE 2~4에서 나온다. 21·30장 SoC에는 없다.
`npu_reset_controller`의 비동기 assert가 RAMB18 제어 핀으로 들어가므로 btnC를 누를 때 내용이 깨질 수 있고, 기본 STA는 이를 분석하지 않는다.
**지금은 기록만 한다.** 동기 리셋으로 바꾸면 검증된 RTL과 비트스트림이 바뀌므로 사용자 승인 뒤 별도 작업으로 한다.

## 5. 26·29장 OOC FAIL

웹 판 `ch26`(WNS -0.468)·`ch29`(-2.811)는 FAIL, 코드 기준인 `part03` VS Code 판은 PASS(`68fd5b6`)이다.
안내서가 어느 판의 판정인지 표시하거나 VS Code 판 증거를 읽게 해야 한다.

## 6. VS Code가 작업 경계 밖에서 고친 것

- `200eedc`: `tools/vivado/ooc_timing.tcl` (2절 원인)
- `47c2f79`: `mini_npu/scripts/run_timing_sim.sh`, `timesim_sanitize.py` (SDF 이름 변환)

되돌리지 않았다. 웹에서 검토해 유지 여부를 정한다.

## 7. 지시 11 실행 방식

1절 오류 때문에 `fd65a88`로는 실행할 수 없다. 설계 RTL·XDC가 같은 `47c2f79`의 무수정 사본에서, 같은 배선 후 넷리스트·SDF로 **전체 시나리오**를 실행한다.
증거는 실제 실행 날짜로 `ch12/validation/vivado_impl_timesim_20261122.txt`에 남긴다(지시문의 파일명은 20261120, 생성기는 최신 파일을 읽는다).
지시문 머리말의 `git fetch origin`은 이 PC에서 `git fetch npu`이다(origin은 `amd_soc_rtl`).

## 8. 지시 11-3 회신 (2026-11-22 밤, `restructure/projects` a5d89dc)

| 항목 | 결과 |
|---|---|
| 지시 11: 12장 SDF 전체 | PASS 6/6, 위반 경고 0. `ch12/validation/vivado_impl_timesim_20261122.txt` |
| 1절: `2544442` TB | xvlog, xelab + SDF 역주석 통과. 이 TB로 SDF 시뮬레이션은 실행하지 않음 |
| 3절: 경고 문구 | `WARNING: ... Timing violation in scope ...`. 현재 grep과 일치(2 ns 음성 대조로 확인) |
| 4절: DRC 증거 | `ch12`·`p02`·`p03`·`p04`의 `validation/drc_reqp1840_20261122.txt` |

남은 웹 작업:

1. **먼저 `build_guides.py`·`build_projects.py` 재생성.** 새 증거 때문에 a5d89dc에서 두 `--check`가 실패한다(대상: 11·12장, p02, GUIDE_STATUS).
2. REQP-1840을 페이지에 미해결로 표시한다. 12장 TIMING_SIM PASS는 동작 중 리셋을 검증하지 않는다.
3. 5절(26·29장 판정 기준)은 11-3에 회신이 없고 `GUIDE_STATUS.md`에 여전히 FAIL로 나온다.
