#!/usr/bin/env python3
"""Vivado report_power 결과(vectorless·CPU 구간 SAIF·NPU 구간 SAIF)로 전력·추론당 에너지 표를 만든다.

추론 시간은 5-4 SoC RTL 시뮬레이션 측정 클록(100 MHz)을 쓴다. 모든 값은 Vivado 추정치이며 보드 측정이 아니다.
"""
import argparse
import re
from pathlib import Path

CLK_NS = 10.0
CYCLES = {"cpu": 1_816_547, "npu": 1_080_161}          # 5-4 validation/soc_bench_sim.log
CELLS = ("p3_npu_0", "microblaze_riscv_0", "axi_smc", "microblaze_riscv_0_local_memory")


def num(text, label):
    m = re.search(r"\|\s*" + re.escape(label) + r"\s*\|\s*([0-9.]+)", text)
    return float(m.group(1)) if m else None


def cell_power(text, cell):
    m = re.search(r"^\|\s+" + re.escape(cell) + r"\s+\|\s*([0-9.<]+)", text, re.M)
    return m.group(1) if m else "?"


def confidence(text):
    m = re.search(r"\|\s*Confidence Level\s*\|\s*(\w+)", text)
    return m.group(1) if m else "?"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--rpt", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    rows, energy = [], []
    for mode, title in (("vectorless", "기본 토글률(vectorless)"), ("cpu", "CPU 추론 구간 SAIF"),
                        ("npu", "NPU 추론 구간 SAIF")):
        f = a.rpt / f"power_{mode}.rpt"
        if not f.exists():
            rows.append(f"| {title} | NOT_RUN | | | | | |")
            continue
        t = f.read_text()
        tot, dyn, sta = num(t, "Total On-Chip Power (W)"), num(t, "Dynamic (W)"), num(t, "Device Static (W)")
        rows.append(f"| {title} | {tot:.3f} | {dyn:.3f} | {sta:.3f} | {cell_power(t, 'p3_npu_0')} | "
                    f"{cell_power(t, 'microblaze_riscv_0')} | {confidence(t)} |")
        if mode in CYCLES:
            sec = CYCLES[mode] * CLK_NS * 1e-9
            energy.append((mode, sec, tot, dyn))
    lines = ["# 5-6 SoC 전력·추론당 에너지 추정 (Vivado 2024.2 report_power, 실제 실행)", "",
             "> 5-2 배선 완료 설계. SAIF는 5-4와 같은 SoC 행동 시뮬레이션의 구간별 토글률. **추정치이며 보드 전력 측정이 아니다.**",
             "", "| 활동률 | 전체(W) | 동적(W) | 정적(W) | p3_npu_0(W) | microblaze_riscv_0(W) | 신뢰도 |",
             "|---|---:|---:|---:|---:|---:|---|", *rows, "",
             "| 추론 경로 | 시간(5-4, 100 MHz) | 전체 전력(W) | 추론당 에너지(mJ) | 동적만(mJ) |",
             "|---|---:|---:|---:|---:|"]
    for mode, sec, tot, dyn in energy:
        lines.append(f"| {'CPU 정수 추론' if mode == 'cpu' else 'NPU 종단간'} | {sec * 1e3:.3f} ms | {tot:.3f} | "
                     f"{tot * sec * 1e3:.3f} | {dyn * sec * 1e3:.3f} |")
    if len(energy) == 2:
        (_, sc, tc, dc), (_, sn, tn, dn) = energy
        lines += ["", f"- 추론당 에너지 비(CPU/NPU): 전체 {tc * sc / (tn * sn):.2f}배, 동적 {dc * sc / (dn * sn):.2f}배"]
    log = a.rpt.parent / "vivado_pwr.log"
    if log.exists():
        # 로그의 절대 경로는 파일 이름만 남긴다(개인 경로 비공개)
        match = [re.sub(r"\S*/([^/\s]+\.saif)", r"\1", l.strip()) for l in log.read_text(errors="replace").splitlines()
                 if re.search(r"matched|annotated|SAIF", l, re.I) and "INFO" in l][:6]
        if match:
            lines += ["", "SAIF 매칭(Vivado 로그):", "", *[f"- `{m}`" for m in match]]
    a.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("POWER_SUMMARY " + " ".join(f"{m}_mJ={t * s * 1e3:.3f}" for m, s, t, _ in energy))


if __name__ == "__main__":
    main()
