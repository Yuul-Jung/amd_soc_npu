#!/usr/bin/env python3
"""22장: 드라이버 기록을 RTL에서 재생한 결과(actual)에서 그림마다 점수 10개·클래스를 뽑아 18장 기준 모델과 비교한다."""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ch18" / "reference"))
from precision_rtl import load, scores                    # noqa: E402
from p3_integer_reference import argmax_lowest            # noqa: E402


def main(actual, n):
    w, b, cases = load(8)
    reads = [ln.split() for ln in open(actual)]
    images, cur = [], None
    for op, off, val in reads:
        off, val = int(off), int(val)
        if op == "P":
            cur = {"poll": val}; images.append(cur)
        elif cur is not None and 0x40 <= off <= 0x64:
            cur.setdefault("score", []).append(val - (1 << 32) if val >= 1 << 31 else val)
        elif cur is not None and off == 0x08:
            cur["class"] = val
    if len(images) != n:
        raise SystemExit(f"DRIVER_RTL_COMPARE_FAIL images={len(images)} expected={n}")
    for k, img in enumerate(images):
        s = scores(cases[k][2], w, b)
        if img.get("score") != s or img.get("class") != argmax_lowest(s) or not img["poll"] & 2:
            raise SystemExit(f"DRIVER_RTL_COMPARE_FAIL image={k} rtl={img} python={s}")
    print(f"DRIVER_RTL_COMPARE_PASS images={n} scores={10 * n} classes={n}")


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]))
