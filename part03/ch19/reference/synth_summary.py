#!/usr/bin/env python3
"""19장: Vivado OOC 합성 보고서(utilization·timing_summary)를 요약표로 만든다(표준 라이브러리).

원본 보고서에는 호스트 이름·경로가 있어 저장소에 넣지 않고, 수치와 임계 경로 끝점만 기록한다.
"""
import argparse
import re
from pathlib import Path

CONFIGS = [
    ("pe1_int8", "PE1 INT8", "p3_group10_core #(64,1)"),
    ("pe4_int8", "PE4 INT8", "p3_group10_core #(64,10) — 14장 기본"),
    ("pe8a_int8", "PE8 코어 A INT8", "p3_group10_core #(64,6)"),
    ("pe8b_int8", "PE8 코어 B INT8", "p3_group10_core #(64,4)"),
    ("pe4_int16", "PE4 INT16", "p3_group10_core DATA_W 16·ACC_W 38"),
    ("tile784_int8", "17장 Tile INT8", "p3_tile784_10 기본"),
    ("tile784_int16", "18장 Tile INT16", "p3_tile784_10 DATA_W 16"),
]


def util(text, label):
    m = re.search(r"^\|\s*" + re.escape(label) + r"\*?\s*\|\s*([0-9.]+)", text, re.M)
    return m.group(1) if m else "?"


def timing(text):
    m = re.search(r"WNS\(ns\).*\n.*\n\s*(-?[0-9.]+)\s+(-?[0-9.]+)\s+(\d+)", text)
    src = re.search(r"^\s*Source:\s+(\S+)", text, re.M)
    dst = re.search(r"^\s*Destination:\s+(\S+)", text, re.M)
    dly = re.search(r"Data Path Delay:\s+([0-9.]+)ns", text)
    lvl = re.search(r"Logic Levels:\s+(\d+)", text)
    return (m.groups() if m else ("?", "?", "?"),
            src.group(1) if src else "?", dst.group(1) if dst else "?",
            dly.group(1) if dly else "?", lvl.group(1) if lvl else "?")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--rpt", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--version", default="?")
    a = p.parse_args()
    rows, paths, n_fail = [], [], 0
    for key, name, desc in CONFIGS:
        u = (a.rpt / f"{key}_utilization.rpt").read_text()
        (wns, tns, fail), src, dst, dly, lvl = timing((a.rpt / f"{key}_timing.rpt").read_text())
        n_fail += wns.startswith("-")
        rows.append(f"| {name} | `{desc}` | {util(u, 'DSPs')} | {util(u, 'Block RAM Tile')} | "
                    f"{util(u, 'Slice LUTs')} | {util(u, 'LUT as Memory')} | {util(u, 'Slice Registers')} | "
                    f"{wns} | {tns} | {fail} |")
        paths.append(f"| {name} | `{src}` | `{dst}` | {dly} | {lvl} |")
    lines = [
        "# 19장 Vivado OOC 합성 요약 (실제 실행)", "",
        f"> Vivado {a.version}, `synth_design -mode out_of_context`, xc7a35tcpg236-1, `create_clock -period 10.000 clk`.",
        "> **합성 직후 추정치**다. 배치·배선·Timing closure·비트스트림·실물은 하지 않았다(24장·후반 일괄).", "",
        "| 구성 | RTL | DSP48E1 | BRAM Tile | LUT | LUTRAM | FF | WNS(ns) | TNS(ns) | 실패 끝점 |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|", *rows, "",
        "- PE8 = 코어 A + 코어 B (각각 따로 합성한 값의 합으로 읽는다. 공유 x 포트 배선은 포함되지 않음).",
        "- BRAM Tile 0.5 = RAMB18 1개. 14장 코어의 lane별 가중치 bank가 RAMB18로 추론되었다.", "",
        "## 임계 경로 (합성 추정)", "",
        "| 구성 | 시작 | 끝 | Data Path(ns) | Logic Levels |", "|---|---|---|---:|---:|", *paths, "",
    ]
    a.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"SYNTH_OOC_SUMMARY configs={len(CONFIGS)} wns_negative={n_fail} out={a.out.name}")


if __name__ == "__main__":
    main()
