#!/usr/bin/env python3
"""24장: Vivado 보고서(report_soc.tcl 출력)에서 SoC 전체와 NPU(npu_0) 계층의 자원, WNS·TNS·WHS, 임계 경로를 한 표로 뽑는다.

사용: parse_reports.py <보고서 폴더>  → 표 출력, 마지막 줄 REPORT_PARSE_PASS 또는 _FAIL
보고서 형식은 Vivado 2024.2 텍스트 보고서를 기준으로 했다. ⚠ 실제 보고서로 아직 확인하지 않았다(05절은 작성한 견본으로 시험).
"""
from __future__ import annotations
import re
import sys
from pathlib import Path


def table_rows(text, first_col):
    """'| a | b | ... |' 표에서 머리줄(first_col로 시작)을 찾아 행 사전 목록을 만든다."""
    lines = [l for l in text.splitlines() if l.startswith("|")]
    for k, l in enumerate(lines):
        cells = [c.strip() for c in l.strip("|").split("|")]
        if cells and cells[0] == first_col:
            head = cells
            return [dict(zip(head, [c.strip() for c in r.strip("|").split("|")])) for r in lines[k + 1:]]
    return []


def util_hier(text):
    rows = table_rows(text, "Instance")
    want = {"Total LUTs": "LUT", "FFs": "FF", "RAMB36": "RAMB36", "RAMB18": "RAMB18", "DSP Blocks": "DSP"}
    out = {}
    for r in rows:
        name = r.get("Instance", "")
        key = "TOTAL" if not name.startswith("(") and r is rows[0] else None
        if re.search(r"\bnpu_0\b", name):
            key = "NPU"
        if key and key not in out:
            out[key] = {v: float(r[k]) for k, v in want.items() if k in r and re.match(r"^[\d.]+$", r[k])}
    return out


def timing(text):
    m = re.search(r"WNS\(ns\)\s+TNS\(ns\).*?\n\s*-+.*?\n\s*([-\d.]+)\s+([-\d.]+)\s+\d+\s+\d+\s+([-\d.]+)\s+([-\d.]+)", text, re.S)
    return dict(zip(["WNS", "TNS", "WHS", "THS"], map(float, m.groups()))) if m else {}


def critical(text):
    src = re.search(r"Source:\s+(\S+)", text); dst = re.search(r"Destination:\s+(\S+)", text)
    slack = re.search(r"Slack\s*\((MET|VIOLATED)\)\s*:\s*([-\d.]+)ns", text)
    lv = re.search(r"Logic Levels:\s+(\d+)", text)
    return {"from": src and src.group(1), "to": dst and dst.group(1), "slack": slack and float(slack.group(2)),
            "levels": lv and int(lv.group(1))}


def main(d):
    d = Path(d)
    u = util_hier((d / "util_hier.rpt").read_text())
    t = timing((d / "timing_summary.rpt").read_text())
    c = critical((d / "critical_path.rpt").read_text())
    info = dict(l.split(" ", 1) for l in (d / "build_info.txt").read_text().splitlines() if " " in l)
    ok = "TOTAL" in u and "NPU" in u and len(t) == 4 and c["slack"] is not None
    for k in ("TOTAL", "NPU"):
        if k in u:
            share = "" if k == "TOTAL" else "  (" + ", ".join(f"{n} {100 * v / u['TOTAL'][n]:.0f}%" for n, v in u[k].items() if u["TOTAL"].get(n)) + ")"
            print(f"UTIL {k:5s} " + " ".join(f"{n}={v:g}" for n, v in u[k].items()) + share)
    print("TIMING " + " ".join(f"{k}={v:+.3f}" for k, v in t.items()))
    print(f"CRITICAL slack={c['slack']} levels={c['levels']} from={c['from']} to={c['to']}")
    print("BUILD " + " ".join(f"{k}={v}" for k, v in info.items()))
    timing_ok = ok and t["WNS"] >= 0 and t["WHS"] >= 0
    print(f"REPORT_PARSE_{'PASS' if ok else 'FAIL'} timing={'met' if timing_ok else 'NOT_MET'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
