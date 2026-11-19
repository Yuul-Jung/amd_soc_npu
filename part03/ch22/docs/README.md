# 제22장 · Vitis C NPU 드라이버

## 1. 구조

```text
sw/ (MicroBlaze V와 PC가 같은 코드)
  npu_driver.h/.c   레지스터 정의·npu_init·npu_set_bias·npu_infer·cpu_infer
  app.h/.c          app_run(): 표본마다 NPU 추론 + CPU 정수 추론 → 서로·기대값 비교
  main.c            대상 main (베이스 = xparameters.h XPAR_P3_NPU_0_BASEADDR)
  npu_io_xil.c      대상 레지스터 접근 Xil_In32/Xil_Out32
host/
  npu_io_cosim.c    PC 레지스터 접근: FIFO → Icarus 브리지 TB → 20장 AXI BFM → 실제 RTL
  cosim_main.c      PC main: CPU 동점 자체 시험 + app_run(0)
tb/tb_p3_npu_bridge.sv   FIFO 명령 "W/R/Q"를 AXI4-Lite 쓰기·읽기로 실행(SLVERR이면 실패)
reference/gen_model.py   18장 INT8 모델·MNIST 표본 4개·기대 점수 → model_data.h (빌드 산출물)
vitis/vitis_build.py     21장 XSA → standalone 플랫폼 → npu_app.elf (Vitis 2024.2 Python API)
```

| 항목 | 계약 |
|---|---|
| 재사용 | 20장 레지스터 맵·AXI BFM(`ch20/tb/axi_lite_bfm.svh`로 분리해 공용), 17·18장 기준모델, 21장 XSA |
| 베이스 주소 | 드라이버에 고정하지 않는다. 대상은 `XPAR_P3_NPU_0_BASEADDR`(= 0x44a00000, 21장 Address Editor 값과 일치 확인), PC는 0 |
| 순서 | 20장 "CPU 실행 순서": Bias(IDLE) → START → 타일마다 LOAD_READY 대기 · W · X · TILE_GO · X_HELD 해제 대기 → DONE → SCORE_LO → SCORE_HI |
| 오류 | 폴링 중 STATUS.ERROR → `NPU_E_HW`(ERR_CODE는 `npu_last_status`), 폴링 한도 초과 → `NPU_E_TIMEOUT`, OVF → `NPU_E_OVERFLOW` |
| 출력 | 대상은 `xil_printf`(64비트 서식 없음 → 점수는 비교 결과만 출력), PC는 `printf` |

## 2. 실행

```bash
bash part03/ch22/scripts/run_sim.sh                       # PC 협동 시뮬레이션(gcc + Icarus)
VITIS_SETTINGS=<Vitis>/settings64.sh bash part03/ch22/scripts/build_vitis.sh   # ELF 빌드(21장 XSA 필요)
```

기대 출력:

```text
CPU_TIE_SELFTEST pairs=9 bad=0
SAMPLE 0 index=0 label=7 npu_class=7 cpu_class=7 expect=7 scores_match=1 rc=0
SAMPLE 1 index=1 label=2 npu_class=2 cpu_class=2 expect=2 scores_match=1 rc=0
SAMPLE 2 index=92 label=9 npu_class=4 cpu_class=4 expect=4 scores_match=1 rc=0
SAMPLE 3 index=1640 label=9 npu_class=4 cpu_class=4 expect=4 scores_match=1 rc=0
NPU_APP_DONE samples=4 failures=0
RTL_SIM_PASS DRIVER_BRIDGE axi_writes=35917 axi_reads=3781 irq_rising=4
...
#define XPAR_P3_NPU_0_BASEADDR 0x44a00000
   text    data     bss     dec     hex filename
  26856     204    3512   30572    776c npu_app.elf
VITIS_ELF_PASS (빌드만, 실물 실행은 사용자와 함께)
```

표본 2·3은 INT8 모델 자체가 9를 4로 틀리는 사례(18장 평가와 같은 예측)다. NPU·CPU·Python 점수 10개가 모두 같다.

## 3. 검증 결과

- **PC 협동 시뮬레이션:** 같은 C 드라이버·응용이 실제 `p3_npu_axi_lite` RTL을 AXI로 제어해 표본 4개 추론 — NPU 점수 = CPU 정수 추론 = Python 기대값(10개 모두), Class 일치. 드라이버 접근 39,698회 중 SLVERR 0, DONE 인터럽트 상승 4회
- **Vitis 2024.2:** 21장 XSA로 standalone 플랫폼(`microblaze_riscv_0`)과 `npu_app.elf` 빌드 성공, 우리 소스 컴파일 경고 없음. ELF 30.5 KB < LMB 64 KB
- **변이 시험:** SCORE_HI를 LO보다 먼저 읽기(스냅샷 오용) → 점수 불일치 검출, TILE_GO 타일 번호 누락 → 컨트롤러 오류 검출, BIAS_HI 부호 확장 누락 → SLVERR 검출, CPU 동점 규칙 반전 → 자체 시험 검출. X_HELD 대기 제거는 다음 타일의 LOAD_READY 대기가 같은 동기화를 해서 이 RTL에서 동등 변이(대기는 버스 지연에 기대지 않는 핸드셰이크라 유지)

**미검증:** Basys3 실물에서 ELF 실행·UART 출력·인터럽트 서비스(사용자와 함께). 인터럽트는 IRQ 신호까지만 확인했고 INTC·ISR 소프트웨어는 아직 없다(폴링 방식).
