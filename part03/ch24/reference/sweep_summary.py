#!/usr/bin/env python3
"""클록 주기 스윕 결과(배선 후 timing·utilization)를 표로 만든다. 4-4 synth_summary의 파서를 재사용한다."""
import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch19.reference.synth_summary import timing, util  # noqa: E402

NAMES = {"pe4_int8": "PE4 INT8 코어", "pe4_int16": "PE4 INT16 코어",
         "tile784_int8": "4-2 Tile INT8", "axi_npu_int8": "5-1 AXI NPU IP"}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--build", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    res = {}
    for d in sorted(a.build.glob("p*_*")):
        period = float(re.match(r"p([0-9.]+)_", d.name).group(1))
        for rt in (d / "rpt").glob("*_route_timing.rpt"):
            key = rt.name[:-len("_route_timing.rpt")]
            (wns, tns, fail), src, dst, dly, lvl = timing(rt.read_text())
            u = (d / "rpt" / f"{key}_route_utilization.rpt").read_text()
            res.setdefault(key, {})[period] = (float(wns), tns, fail, src, dst, util(u, "Slice LUTs"),
                                              util(u, "Slice Registers"))
    lines = ["# 5-5 클록 주기 스윕 — OOC 합성·배치·배선 (Vivado 실제 실행)", "",
             "> 합성 단계부터 목표 주기로 제약. Fmax(추정) = 1000 / (주기 − WNS) MHz, 통과한 가장 짧은 주기 기준.",
             "> OOC는 칩 I/O를 포함하지 않는다. 실물 동작 주파수가 아니다.", "",
             "| 구성 | 주기(ns) | WNS(ns) | TNS(ns) | 실패 끝점 | LUT | FF | 임계 경로 |",
             "|---|---:|---:|---:|---:|---:|---:|---|"]
    summary = []
    for key in NAMES:
        best = None
        for period in sorted(res.get(key, {}), reverse=True):
            wns, tns, fail, src, dst, lut, ff = res[key][period]
            lines.append(f"| {NAMES[key]} | {period:.3f} | {wns:+.3f} | {tns} | {fail} | {lut} | {ff} | "
                         f"`{src}` → `{dst}` |")
            if wns >= 0:
                fmax = 1000.0 / (period - wns)
                if best is None or period < best[0]:
                    best = (period, wns, fmax)
        summary.append((key, best))
    lines += ["", "| 구성 | 통과한 가장 짧은 주기 | WNS | Fmax 추정(MHz) |", "|---|---:|---:|---:|"]
    for key, best in summary:
        lines.append(f"| {NAMES[key]} | " + (f"{best[0]:.3f} ns | {best[1]:+.3f} | {best[2]:.1f} |"
                                              if best else "— | — | 통과 없음 |"))
    a.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("SWEEP_SUMMARY " + " ".join(f"{k}={b[2]:.1f}MHz" if b else f"{k}=none" for k, b in summary))


if __name__ == "__main__":
    main()
