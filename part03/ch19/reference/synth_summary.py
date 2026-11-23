#!/usr/bin/env python3
"""Vivado OOC 합성·배선 보고서(utilization·timing_summary)를 요약표로 만든다(표준 라이브러리).

원본 보고서에는 호스트 이름·경로가 있어 저장소에 넣지 않고, 수치와 임계 경로 끝점만 기록한다.
"""
import argparse
import re
from pathlib import Path

CONFIGS = [
    ("pe1_int8", "PE1 INT8", "p3_group10_core #(64,1)"),
    ("pe4_int8", "PE4 INT8", "p3_group10_core #(64,10) — 3-2 기본"),
    ("pe8a_int8", "PE8 코어 A INT8", "p3_group10_core #(64,6)"),
    ("pe8b_int8", "PE8 코어 B INT8", "p3_group10_core #(64,4)"),
    ("pe4_int16", "PE4 INT16", "p3_group10_core DATA_W 16·ACC_W 38"),
    ("tile784_int8", "4-2 Tile INT8", "p3_tile784_10 기본"),
    ("tile784_int16", "4-3 Tile INT16", "p3_tile784_10 DATA_W 16"),
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
    p.add_argument("--config", nargs=3, action="append", metavar=("KEY", "NAME", "RTL"),
                   help="요약할 구성. 없으면 4-4 기본 7개")
    p.add_argument("--title", default="4-4 Vivado OOC 합성 요약 (실제 실행)")
    a = p.parse_args()
    configs = [tuple(c) for c in a.config] if a.config else CONFIGS
    rows, paths, routed, n_fail, n_route_fail = [], [], [], 0, 0
    for key, name, desc in configs:
        u = (a.rpt / f"{key}_utilization.rpt").read_text()
        (wns, tns, fail), src, dst, dly, lvl = timing((a.rpt / f"{key}_timing.rpt").read_text())
        n_fail += wns.startswith("-")
        rt = a.rpt / f"{key}_route_timing.rpt"
        if rt.exists():
            ru = (a.rpt / f"{key}_route_utilization.rpt").read_text()
            (rw, rtn, rf), rs, rd, rdl, rl = timing(rt.read_text())
            n_route_fail += rw.startswith("-")
            routed.append(f"| {name} | {util(ru, 'DSPs')} | {util(ru, 'Block RAM Tile')} | "
                          f"{util(ru, 'Slice LUTs')} | {util(ru, 'Slice Registers')} | {rw} | {rtn} | {rf} | "
                          f"`{rs}` → `{rd}` | {rdl} |")
        rows.append(f"| {name} | `{desc}` | {util(u, 'DSPs')} | {util(u, 'Block RAM Tile')} | "
                    f"{util(u, 'Slice LUTs')} | {util(u, 'LUT as Memory')} | {util(u, 'Slice Registers')} | "
                    f"{wns} | {tns} | {fail} |")
        paths.append(f"| {name} | `{src}` | `{dst}` | {dly} | {lvl} |")
    lines = [
        f"# {a.title}", "",
        f"> Vivado {a.version}, `synth_design -mode out_of_context`, xc7a35tcpg236-1, `create_clock -period 10.000 clk`.",
        "> 첫 표는 **합성 직후 추정치**, 배선 후 결과는 아래 별도 표. 비트스트림·실물은 하지 않았다.", "",
        "| 구성 | RTL | DSP48E1 | BRAM Tile | LUT | LUTRAM | FF | WNS(ns) | TNS(ns) | 실패 끝점 |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|", *rows, "",
        *([] if a.config else [
            "- PE8 = 코어 A + 코어 B (각각 따로 합성한 값의 합으로 읽는다. 공유 x 포트 배선은 포함되지 않음).",
            "- BRAM Tile 0.5 = RAMB18 1개. 3-2 코어의 lane별 가중치 bank가 RAMB18로 추론되었다."]), "",
        "## 임계 경로 (합성 추정)", "",
        "| 구성 | 시작 | 끝 | Data Path(ns) | Logic Levels |", "|---|---|---|---:|---:|", *paths, "",
    ]
    if routed:
        lines += ["## OOC 배치·배선 후 (opt_design → place_design → route_design)", "",
                  "> 최상위 포트를 FPGA 핀에 묶지 않은 OOC 구현이다. 칩 전체 Top·I/O·비트스트림·실물은 별도.", "",
                  "| 구성 | DSP | BRAM Tile | LUT | FF | WNS(ns) | TNS(ns) | 실패 끝점 | 임계 경로 | Data Path(ns) |",
                  "|---|---:|---:|---:|---:|---:|---:|---:|---|---:|", *routed, ""]
    a.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    tail = f" routed={len(routed)} route_wns_negative={n_route_fail}" if routed else ""
    print(f"SYNTH_OOC_SUMMARY configs={len(configs)} wns_negative={n_fail}{tail} out={a.out.name}")


if __name__ == "__main__":
    main()
