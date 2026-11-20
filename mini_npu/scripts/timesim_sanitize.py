#!/usr/bin/env python3
"""(추가) 배선 후 타이밍 넷리스트·SDF의 대괄호 이스케이프 이름을 일반 식별자로 바꾼다.

xsim 2024.2는 SDF INTERCONNECT의 대상 인스턴스 이름이 `reg\\[0\\]`처럼 대괄호
이스케이프를 포함하면 그 배선 지연을 적용하지 않는다(오류·경고 없음). 12장 넷리스트는
클록 배선 지연 1,299개 중 1,247개가 이런 이름이라, 시뮬레이션에서만 FF마다 클록이
최대 약 1.7 ns 어긋나는 가짜 hold 경합이 생겨 UART 수신 valid 펄스가 사라졌다.
(STA WHS +0.064 ns와 모순 — 실제 칩 문제가 아님.)

넷리스트의 이스케이프 식별자(`\\name[3] `)와 SDF의 `\\[` `\\]`를 같은 규칙으로 바꿔
두 파일의 이름이 그대로 대응하게 한다. 지연 값은 하나도 건드리지 않는다.

사용: timesim_sanitize.py <in.v> <in.sdf> <out.v> <out.sdf>
"""
import re
import sys

MAP = {"[": "__LB", "]": "RB__", ".": "__DOT__", ":": "__CLN__"}


def mangle(name: str) -> str:
    return "".join(MAP.get(c, c) for c in name)


def main() -> int:
    vin, sin, vout, sout = sys.argv[1:5]
    v = open(vin).read()
    # Verilog 이스케이프 식별자: 백슬래시 + 공백이 아닌 문자들 + 공백 하나.
    def fix_v(m):
        body = m.group(1)
        new = mangle(body)
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", new):
            return m.group(0)  # 바꿔도 합법 식별자가 아니면 그대로 둔다.
        return new + " "
    v, nv = re.subn(r"\\([^\s]+) ", fix_v, v)
    # $sdf_annotate가 새 SDF를 보게 한다.
    v, na = re.subn(r'\$sdf_annotate\("[^"]*"', '$sdf_annotate("%s"' % sout, v)
    if na != 1:
        print("TIMESIM_SANITIZE_FAIL sdf_annotate count=%d" % na)
        return 1
    s = open(sin).read()
    s, ns = re.subn(r"\\([\[\].:])", lambda m: MAP[m.group(1)], s)
    open(vout, "w").write(v)
    open(sout, "w").write(s)
    print("TIMESIM_SANITIZE_OK verilog_ids=%d sdf_escapes=%d" % (nv, ns))
    return 0


if __name__ == "__main__":
    sys.exit(main())
