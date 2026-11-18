#!/usr/bin/env python3
"""27장: 18장 INT8 모델 + 숫자별 시험 그림 10장(model/demo_cases_int8.txt)을 C 헤더로 만든다 (22장 헤더와 같은 이름)."""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ch18" / "reference"))
from precision_rtl import load    # noqa: E402


def demo_cases():
    rows = [list(map(int, l.split())) for l in open(ROOT / "ch27" / "model" / "demo_cases_int8.txt")]
    return [(r[0], r[1], r[2:]) for r in rows]


def main(out):
    w, b, _ = load(8)
    cs = demo_cases()
    L = ["/* 자동 생성: ch27/reference/gen_demo_header.py — 직접 고치지 않는다 */", "#ifndef MODEL_INT8_H", "#define MODEL_INT8_H",
         "#include <stdint.h>", f"#define TEST_N {len(cs)}", "static const int8_t MODEL_W[10][784] = {"]
    L += ["  {" + ",".join(map(str, r)) + "}," for r in w]
    L += ["};", "static const int32_t MODEL_B[10] = {" + ",".join(map(str, b)) + "};", f"static const uint8_t TEST_X[{len(cs)}][784] = {{"]
    L += ["  {" + ",".join(map(str, x)) + "}," for _, _, x in cs]
    L += ["};", "static const uint8_t TEST_LABEL[%d] = {%s};" % (len(cs), ",".join(str(l) for _, l, _ in cs)), "#endif", ""]
    Path(out).write_text("\n".join(L))
    print(f"DEMO_HEADER_OK images={len(cs)}")


if __name__ == "__main__":
    main(sys.argv[1])
