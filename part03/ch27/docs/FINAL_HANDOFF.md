# 제3부 13~27장 최종 인계 (2026-11-18)

> 저장소 `amd_soc_rtl`, 브랜치 `work/part03-ch13-19`(로컬 커밋, GitHub 반영은 ChatGPT 담당). 결과는 실제 실행한 도구 기준이며,
> **Basys3 실물은 전부 NOT_RUN**(`docs/BOARD_CHECKLIST.md`로 사용자와 함께).

## 1. 장별 상태

| 장 | 내용 | 커밋 | 검증 종류 | 핵심 결과 |
|---|---|---|---|---|
| 13 | 8×8 INT8 프레임 버퍼 | 633c5fc | RTL sim | frames 36, 짧은·긴 프레임 |
| 14 | 4PE 4+4+2 10분류 코어 | 5c89512, 189a375, 8150a7d, 2e45bf1 | RTL sim + OOC 배선 | cases 41, 206클록, 파라미터 DATA_W 등, argmax 타이밍 수정 |
| 15 | Dense 계층 재사용 | 16c6988 | RTL sim | 64→10·64→8·8→10 |
| 16 | 64→8→10 MLP | 2505155 | RTL sim | 180클록, 재양자화 |
| 17 | 784입력 13타일 외부 누산 | 995128a, 8150a7d, 2e45bf1 | RTL sim + OOC 배선 | 부분합 3,380 비트 일치, Bias 1회, 41/42비트 |
| 18 | Float·INT8·INT16 정밀도 | 9ff54d0 | PC 평가 + RTL sim | t10k Float 92.60%, INT8 92.56%, INT16 92.60%, INT16 RTL 41비트 검증 |
| 19 | 1·4·8PE 비교 | 1498e7e | RTL sim + OOC 배선 | 700/206/138클록, 적재 병목, argmax 결함 발견 |
| 20 | AXI4-Lite NPU IP | 31ffd79 | BFM RTL sim + OOC 배선 + IP 패키징 | 784 추론 7회 일치, SLVERR 16, WNS +0.223 |
| 21 | MicroBlaze V + NPU SoC | 8a3c4a6 | Vivado 칩 전체 구현·Bitstream·XSA | WNS +0.219 / WHS +0.021, 원본 무변경 |
| 22 | C 드라이버·Vitis | 22ea723 | C·RTL 협동 sim + Vitis ELF | NPU = CPU = Python, ELF 30.5 KB |
| 23 | CPU 대 NPU | 3b36549 | SoC 전체 xsim(실제 MicroBlaze V) | CPU 1,816,547 / NPU 종단간 1,080,161 클록 |
| 24 | 자원·타이밍 | fd137d6 | OOC 배선 주기 스윕 | Fmax 코어 146·Tile 101·AXI 105 MHz |
| 25 | 전력·에너지 | 2674513 | Vivado report_power + 구간별 SAIF | CPU 4.541 mJ vs NPU 2.733 mJ/추론(1.66배), SAIF 매칭 13% |
| 26 | 3×3 합성곱(선택) | 505be9e | RTL sim + OOC 배선 | 936출력 일치, WNS +4.647 |
| 27 | 통합 실행기·인계 | (이 장 커밋) | `run_all.sh` LEVEL=sim PASS | 이 문서, 실물 점검표 |

## 2. 재현

```bash
LEVEL=sim  bash part03/ch27/scripts/run_all.sh                       # RTL·Python·C (약 10분)
LEVEL=pc   MNIST_DIR=<MNIST raw> bash part03/ch27/scripts/run_all.sh  # + 18장 전체 평가
LEVEL=fpga SOC11_DIR=<제1부 11장 soc11_user_top> VIVADO_SETTINGS=<…>/settings64.sh \
           VITIS_SETTINGS=<…>/settings64.sh bash part03/ch27/scripts/run_all.sh   # + Vivado·Vitis
LEVEL=full …                                                          # + SoC xsim·전력 (수 시간)
```

결과 표: `ch27/validation/run_all_summary.md`, 단계별 로그: `ch27/validation/logs/`.

## 3. 결정·정책 기록

- 14장 코어는 파라미터 확장(DATA_W/ACC_W/BIAS_W/SCORE_W)과 argmax 타이밍 수정만 했고, 기본 동작·사이클은 회귀 로그로 동일함을 확인했다.
- 17장 Bias 중복 방지: 코어 Bias 포트를 0으로 고정, 실제 Bias는 13타일 뒤 1회.
- 20장 응답 규칙: 버스 수준 거부는 SLVERR(효과 없음), NPU 동작 오류는 STATUS.ERROR·ERR_CODE.
- 21장은 원본 제1부 11장 프로젝트를 열지 않고 `cp -a` 복제본만 사용(트리 해시 전후 동일).
- Vivado IP 폴더·프로젝트·Bitstream·XSA·ELF는 빌드 산출물(`build/`, 저장소 제외). 정본은 각 장 `rtl/`·`sw/`·`synth/`.

## 4. 남은 일·알려진 한계

1. **실물:** Basys3 다운로드·UART·인터럽트·사이클 실측 (BOARD_CHECKLIST B1~B7).
2. **성능 병목:** NPU 종단간 시간의 99% 이상이 AXI4-Lite 단어 단위 적재. 가중치 상주 BRAM(62.7 kbit) 또는 DMA/버스트가 다음 개선 대상.
3. **타이밍 여유:** 17장 컨트롤러 argmax 1·2단이 Fmax 101 MHz를 정한다. 클록당 비교 1단 분할안(done +2클록)을 문서화만 했다.
4. **빌드 설정:** Vitis 기본 Debug(-O0), MicroBlaze V rv32i(M 확장 없음). 최적화 빌드·M 확장 비교는 아직 없다.
5. **인터럽트:** IRQ 신호와 INTC 연결까지 확인. ISR 소프트웨어는 없다(폴링 드라이버).
6. **28~31장 응용 과제:** 아직 착수하지 않았다.
