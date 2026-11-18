#!/usr/bin/env python3
"""27장 정적 검사: soc_npu27_top 포트(비트 단위)와 soc_npu27.xdc 핀 배정이 같고, 핀이 겹치지 않으며,
7세그먼트 핀이 12장 basys3_npu.xdc와 같은지 본다 (Vivado를 대신하지 않음)."""
import re
import sys
from pathlib import Path

R = Path(__file__).resolve().parents[2]
top = (R / "ch27/rtl/soc_npu27_top.v").read_text()
ports = []
for _, w, n in re.findall(r"(input|output)\s+wire\s+(\[\d+:\d+\])?\s*(\w+)", top):
    if w:
        hi, lo = map(int, re.findall(r"\d+", w))
        ports += [f"{n}[{i}]" for i in range(lo, hi + 1)]
    else:
        ports.append(n)


def pins(path):
    return {p1 or p2: pin for pin, p1, p2 in re.findall(r"PACKAGE_PIN\s+(\w+)[^\[]*\[get_ports\s+(?:\{([^}]+)\}|(\w+))\]", path.read_text())}


x27, x12 = pins(R / "ch27/constraints/soc_npu27.xdc"), pins(R / "mini_npu/constraints/basys3_npu.xdc")
miss, extra = sorted(set(ports) - set(x27)), sorted(set(x27) - set(ports))
dup = len(x27.values()) != len(set(x27.values()))
seg_diff = [p for p in x27 if re.match(r"(seg|an)\[|dp$", p) and x12.get(p) != x27[p]]
ok = not (miss or extra or dup or seg_diff)
print(f"{'TOP_XDC_STATIC_CHECK_PASS' if ok else 'TOP_XDC_STATIC_CHECK_FAIL'} ports={len(ports)} pins={len(x27)} "
      f"missing={miss} extra={extra} duplicate={dup} seg_pins_differ_from_ch12={seg_diff}")
sys.exit(0 if ok else 1)
