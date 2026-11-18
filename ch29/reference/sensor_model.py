#!/usr/bin/env python3
"""29장 기준 모델: 가상 센서 4채널 × 16샘플(12비트) → 유효성 검사(범위·고착·순서) → INT8 스케일 → Dense 64→4 → 판정.

상태: 0 NORMAL, 1 HOT(채널0 상승), 2 VIBRATION(채널1 진동), 3 DRIFT(채널2 천천히 벗어남), 4 UNKNOWN(점수 차 < MARGIN), 5 FAULT.
모델은 합성 데이터(이 파일이 만든 가상 센서 값)로 학습한 소프트맥스 회귀이며, 실제 센서 데이터가 아니다.
--train: 학습·양자화해 model/sensor_int8.txt 저장 (numpy 필요) / --out·--actual: RTL 시험 벡터·비교 (표준 라이브러리)."""
from __future__ import annotations
import argparse
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "host_tools"))
from p3_integer_reference import dot_signed               # noqa: E402

MODEL = ROOT / "ch29" / "model" / "sensor_int8.txt"
MIN_RAW, MAX_RAW, STUCK_N, MARGIN = 100, 4000, 8, 3000
NAMES = ["NORMAL", "HOT", "VIBRATION", "DRIFT", "UNKNOWN", "FAULT"]


def scenario(kind, rng, mix=None):
    """16×4 원시값 (t 우선: 인덱스 = t*4 + ch)."""
    out = []
    for t in range(16):
        v = [2048 + rng.randint(-40, 40) for _ in range(4)]
        if kind == 1: v[0] += 60 * t                          # 온도 상승
        if kind == 2: v[1] += int(700 * math.sin(t * 1.9))     # 진동
        if kind == 3: v[2] -= 25 * t * t // 4                  # 느린 이탈 (가속)
        if mix: v[0] += int(mix[0] * 60 * t); v[1] += int(mix[1] * 700 * math.sin(t * 1.9))
        out += v
    return out


def scale(raw):
    return max(-128, min(127, (raw - 2048) >> 4))


def guard(raw, chans=None):
    """고장 비트: bit0 범위, bit1 고착(같은 채널 같은 값 8번 연속), bit2 순서."""
    fault = 0
    chans = chans or [i % 4 for i in range(64)]
    if any(c != i % 4 for i, c in enumerate(chans)): fault |= 4
    if any(not MIN_RAW <= r <= MAX_RAW for r in raw): fault |= 1
    for ch in range(4):
        run = 1
        for t in range(1, 16):
            run = run + 1 if raw[t * 4 + ch] == raw[(t - 1) * 4 + ch] else 1
            if run >= STUCK_N: fault |= 2
    return fault


def decide(raw, w, b, chans=None):
    f = guard(raw, chans)
    if f: return 5, f, [0] * 4
    x = [scale(r) for r in raw]
    s = [dot_signed(x, row) + bb for row, bb in zip(w, b)]
    order = sorted(range(4), key=lambda i: (-s[i], i))
    return (order[0] if s[order[0]] - s[order[1]] >= MARGIN else 4), 0, s


def train():
    import numpy as np
    rng = random.Random(29)
    X, Y = [], []
    for _ in range(2000):
        k = rng.randrange(4)
        X.append([scale(r) / 128 for r in scenario(k, rng)]); Y.append(k)
    X, Y = np.array(X, np.float32), np.array(Y)
    W = np.zeros((64, 4), np.float32); B = np.zeros(4, np.float32); oh = np.eye(4, dtype=np.float32)[Y]
    for _ in range(300):
        z = X @ W + B; z -= z.max(1, keepdims=True); p = np.exp(z); p /= p.sum(1, keepdims=True)
        g = (p - oh) / len(X); W -= 2.0 * X.T @ g; B -= 2.0 * g.sum(0)
    s = float(np.abs(W).max()) / 127
    wq = np.clip(np.rint(W / s), -128, 127).astype(int).T
    bq = np.rint(B / (s / 128)).astype(int)                 # x = scale/128 단위 → 정수 점수 단위
    MODEL.parent.mkdir(exist_ok=True)
    MODEL.write_text("\n".join(" ".join(map(str, r)) for r in wq) + "\n" + " ".join(map(str, bq)) + "\n")
    rng = random.Random(2929); right = 0
    w, b = load()
    for _ in range(400):
        k = rng.randrange(4); st, _, _ = decide(scenario(k, rng), w, b); right += st == k
    print(f"SENSOR_MODEL_TRAINED synthetic_test_accuracy={right / 4:.1f}% (합성 데이터 400개, UNKNOWN은 틀림으로 셈)")


def load():
    rows = [list(map(int, l.split())) for l in MODEL.read_text().splitlines()]
    return rows[:4], rows[4]


def cases():
    rng = random.Random(299)
    out = [(f"{NAMES[k]}_{i}", scenario(k, rng), None) for k in range(4) for i in range(2)]
    w, b = load()
    for _ in range(500):                                     # 점수 차가 작은 섞인 경우를 하나 찾는다
        raw = scenario(0, rng, mix=(rng.random(), rng.random()))
        if decide(raw, w, b)[0] == 4:
            out.append(("ambiguous", raw, None)); break
    raw = scenario(0, rng); raw[17] = 50; out.append(("range_low", raw, None))
    raw = scenario(0, rng)
    for t in range(4, 13): raw[t * 4 + 3] = 2100
    out.append(("stuck_ch3", raw, None))
    ch = [i % 4 for i in range(64)]; ch[30], ch[31] = ch[31], ch[30]
    out.append(("order", scenario(0, rng), ch))
    return out


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--train", action="store_true"); ap.add_argument("--out"); ap.add_argument("--actual")
    a = ap.parse_args()
    if a.train:
        train(); return
    w, b = load(); cs = cases()
    got = [decide(r, w, b, c)[0] for _, r, c in cs]
    assert set(got) == {0, 1, 2, 3, 4, 5}, got
    print(f"PYTHON_SENSOR_SELF_TEST_PASS cases={len(cs)} states={'/'.join(NAMES[s] for s in sorted(set(got)))}")
    if a.out and not a.actual:
        with open(a.out, "w") as f:
            f.writelines(" ".join(map(str, row)) + "\n" for row in w)
            f.write(" ".join(map(str, b)) + "\n")
            for n, (name, raw, ch) in enumerate(cs):
                ch = ch or [i % 4 for i in range(64)]
                f.write(f"{n} {name} " + " ".join(f"{c} {r}" for c, r in zip(ch, raw)) + "\n")
    if a.actual:
        rows = {int(p[0]): list(map(int, p[1:])) for p in (l.split() for l in open(a.actual))}
        for n, (name, raw, ch) in enumerate(cs):
            st, f, s = decide(raw, w, b, ch)
            if rows.get(n) != [st, f] + s:
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL case={name} rtl={rows.get(n)} py={[st, f] + s}")
            print(f"STATE {name:12s} → {NAMES[st]}" + (f" fault=0b{f:03b}" if f else f" margin={sorted(s)[-1] - sorted(s)[-2]}"))
        print(f"PYTHON_RTL_COMPARE_PASS cases={len(cs)}")


if __name__ == "__main__":
    main()
