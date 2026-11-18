#!/usr/bin/env python3
"""22장: 18장 INT8 모델(실제 MNIST 학습)과 시험 앞 N장을 C 헤더 model_int8.h로 만든다."""
from __future__ import annotations
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ch18" / "reference"))
from precision_rtl import load    # noqa: E402


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--n", type=int, default=5); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    w, b, cases = load(8)
    cases = cases[:a.n]
    L = ["/* 자동 생성: ch22/reference/gen_model_header.py — 직접 고치지 않는다 (18장 실제 MNIST INT8 모델) */",
         "#ifndef MODEL_INT8_H", "#define MODEL_INT8_H", "#include <stdint.h>",
         f"#define TEST_N {len(cases)}",
         "static const int8_t MODEL_W[10][784] = {"]
    L += ["  {" + ",".join(map(str, row)) + "}," for row in w]
    L += ["};", "static const int32_t MODEL_B[10] = {" + ",".join(map(str, b)) + "};",
          f"static const uint8_t TEST_X[{len(cases)}][784] = {{"]
    L += ["  {" + ",".join(map(str, x)) + "}," for _, _, x in cases]
    L += ["};", "static const uint8_t TEST_LABEL[%d] = {%s};" % (len(cases), ",".join(str(l) for _, l, _ in cases)), "#endif", ""]
    Path(a.out).write_text("\n".join(L))
    print(f"MODEL_HEADER_OK images={len(cases)} bytes={Path(a.out).stat().st_size}")


if __name__ == "__main__":
    main()
