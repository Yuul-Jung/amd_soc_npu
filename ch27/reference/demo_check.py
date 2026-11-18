#!/usr/bin/env python3
"""27장: 펌웨어 기록을 RTL에서 재생한 결과로 그림 10장의 점수·클래스를 18장 기준과 비교하고,
펌웨어가 LED·7세그먼트에 보낼 워드를 클래스에서 계산해 표로 낸다."""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "ch18" / "reference"), str(ROOT / "ch27" / "reference")]
from precision_rtl import load, scores                   # noqa: E402
from p3_integer_reference import argmax_lowest           # noqa: E402
from gen_demo_header import demo_cases                    # noqa: E402

GLYPH = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]


def led_word(cls):
    return (1 << 15) | (cls << 10) | (1 << cls)


def main(actual, led_log):
    w, b, _ = load(8)
    cs = demo_cases()
    images, cur = [], None
    for op, off, val in (ln.split() for ln in open(actual)):
        off, val = int(off), int(val)
        if op == "P":
            cur = {}; images.append(cur)
        elif cur is not None and 0x40 <= off <= 0x64:
            cur.setdefault("score", []).append(val - (1 << 32) if val >= 1 << 31 else val)
        elif cur is not None and off == 0x08:
            cur["class"] = val
    if len(images) != len(cs):
        raise SystemExit(f"DEMO_RTL_COMPARE_FAIL images={len(images)}")
    right = 0
    for k, ((idx, label, x), img) in enumerate(zip(cs, images)):
        s = scores(x, w, b); c = argmax_lowest(s)
        if img.get("score") != s or img.get("class") != c:
            raise SystemExit(f"DEMO_RTL_COMPARE_FAIL sw={k}")
        right += c == label
        print(f"DEMO sw={k} mnist_test[{idx}] label={label} class={c} led=0x{led_word(c):04X} fnd={GLYPH[c]} {'OK' if c == label else 'MISS'}")
    leds = [tuple(map(int, l.split())) for l in open(led_log)]
    if len(leds) != 11 or leds[-1] != (12, 0) or any(v >> 14 & 1 for _, v in leds):
        raise SystemExit(f"DEMO_LED_SEQUENCE_FAIL {leds}")
    print(f"DEMO_RTL_COMPARE_PASS images=10 correct={right}/10 led_writes=11 (sw=12 → 표시 지움)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
