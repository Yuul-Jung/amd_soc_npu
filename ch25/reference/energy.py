#!/usr/bin/env python3
"""25장: 전력 보고서 두 개(A 기본, B NPU 활동 가정)와 23장 시간(CSV)으로 추론 1회 에너지를 추정한다.

E = P × t. P는 report_power의 Total On-Chip Power(W), t는 23장 보드 측정 클록 / 100 MHz.
CPU 추론 에너지는 A(NPU 쉬는 상태)를, NPU 추론 에너지는 B(NPU 활동 가정)를 쓴다 — 둘 다 추정이다.
보고서 형식은 Vivado 2024.2 텍스트 보고서를 가정했다(⚠ 실제 보고서로 미확인).
"""
from __future__ import annotations
import csv
import re
import sys
from pathlib import Path


def power(text):
    tot = re.search(r"\|\s*Total On-Chip Power \(W\)\s*\|\s*([\d.]+)", text)
    dyn = re.search(r"\|\s*Dynamic \(W\)\s*\|\s*([\d.]+)", text)
    sta = re.search(r"\|\s*Device Static \(W\)\s*\|\s*([\d.]+)", text)
    conf = re.search(r"\|\s*Confidence Level\s*\|\s*(\w+)", text)
    return {"total": float(tot.group(1)), "dynamic": float(dyn.group(1)), "static": float(sta.group(1)),
            "confidence": conf.group(1) if conf else "?"} if tot and dyn and sta else None


def main(rep_dir, csv_path=None):
    d = Path(rep_dir)
    a = power((d / "power_default.rpt").read_text())
    b = power((d / "power_npu_active.rpt").read_text())
    if not a or not b:
        print("POWER_PARSE_FAIL"); return 1
    for k, p in (("A_default", a), ("B_npu_active", b)):
        print(f"POWER {k} total={p['total']:.3f}W dynamic={p['dynamic']:.3f}W static={p['static']:.3f}W confidence={p['confidence']}")
    if csv_path and Path(csv_path).exists():
        rows = [r for r in csv.DictReader(open(csv_path)) if r.get("image", "").isdigit()]
        cpu = sum(int(r["cpu_clk"]) for r in rows) / len(rows) / 100e6
        npu = sum(int(r["npu_load_clk"]) + int(r["npu_run_clk"]) for r in rows) / len(rows) / 100e6
        print(f"ENERGY cpu={a['total'] * cpu * 1e6:.2f}uJ (P_A×{cpu * 1e6:.1f}us)  npu={b['total'] * npu * 1e6:.2f}uJ (P_B×{npu * 1e6:.1f}us)  [추정]")
    else:
        print("ENERGY NOT_RUN (23장 보드 측정 CSV 없음)")
    print("POWER_PARSE_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
