#!/usr/bin/env python3
"""MNIST 784→10 Float·INT8·INT16 정밀도 비교 기준모델(표준 라이브러리만 사용).

같은 Float32 가중치(mnist_linear_f32.json)를 INT8·INT16으로 양자화하고, 같은 시험셋·전처리로 비교한다.
양자화 계약(대칭, zero-point 0, N = 8 또는 16, Q = 2^(N-1) - 1):
  x_q = round_half_away(pixel * Q / 255)                 0..Q      (s_x = 1/Q,  x ≈ x_q·s_x)
  w_q = sat_N(round_half_away(W / s_w)),  s_w = max|W|/Q  -Q..Q
  b_q = sat_40(round_half_away(b / (s_x·s_w)))           누산과 같은 단위
  z_q[c] = Σ x_q·w_q[c] + b_q[c]  (4-2 13타일 RTL과 같은 정수, 반올림·포화 없음)  → argmax(동점 낮은 번호)
반올림·포화는 PC 양자화 단계에서 한 번만 일어난다. RTL은 넓은 폭으로 정확히 누산한다(ovf=0 확인).
모드: --eval(시험셋 전체, MNIST 필요), --rtl-vectors(커밋된 표본으로 RTL 벡터), --actual(RTL 비교).
"""
import argparse
import json
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.host_tools.p3_integer_reference import argmax_lowest, dot_tiled_64, sat_int8  # noqa: E402
from part03.ch17.reference.tile784_reference import (  # noqa: E402
    compare, model, padding, write_vectors,
)

HERE = Path(__file__).resolve().parent
MODEL = HERE / "mnist_linear_f32.json"
SAMPLES = HERE / "mnist_rtl_samples.txt"
BIAS_W, ACC_W = 40, 41
N_IN, N_CLASS = 784, 10


def qmax(bits):
    return (1 << (bits - 1)) - 1


def sat_signed(v, bits):
    return max(-(1 << (bits - 1)), min((1 << (bits - 1)) - 1, v))


def round_half_away(v):
    """실수 반올림: 절반은 0에서 먼 쪽(Python round()의 짝수 반올림과 다름)."""
    return int(math.copysign(math.floor(abs(v) + 0.5), v))


def div_round_away(n, d):
    """정수 n/d (d > 0) 반올림, 절반은 0에서 먼 쪽."""
    q = (2 * abs(n) + d) // (2 * d)
    return -q if n < 0 else q


def quantize_model(m, bits):
    q = qmax(bits)
    max_w = max(abs(v) for row in m["weight"] for v in row)
    s_x, s_w = 1.0 / q, max_w / q
    w_q = [[sat_signed(round_half_away(v / s_w), bits) for v in row] for row in m["weight"]]
    b_q = [sat_signed(round_half_away(v / (s_x * s_w)), BIAS_W) for v in m["bias"]]
    return {"bits": bits, "q": q, "s_x": s_x, "s_w": s_w, "max_w": max_w, "w": w_q, "b": b_q}


def quantize_x(pixels, bits):
    return [div_round_away(p * qmax(bits), 255) for p in pixels]


def int_logits(x_q, qm):
    return [dot_tiled_64(x_q, qm["w"][c]) + qm["b"][c] for c in range(N_CLASS)]


def float_logits(pixels, m):
    x = [p / 255.0 for p in pixels]
    return [sum(a * w for a, w in zip(x, row)) + b for row, b in zip(m["weight"], m["bias"])]


def read_idx(path):
    raw = path.read_bytes()
    ndim = raw[3]
    dims = [int.from_bytes(raw[4 + 4 * i:8 + 4 * i], "big") for i in range(ndim)]
    body = raw[4 + 4 * ndim:]
    if ndim == 1:
        return list(body)
    step = dims[1] * dims[2]
    return [list(body[i * step:(i + 1) * step]) for i in range(dims[0])]


def selftest():
    assert [round_half_away(v) for v in (-2.5, -1.5, -0.5, 0.5, 1.5, 2.5)] == [-3, -2, -1, 1, 2, 3]
    assert [round(v) for v in (0.5, 1.5, 2.5)] == [0, 2, 2]   # Python round()는 짝수 반올림
    assert [div_round_away(n, 2) for n in (-5, -3, -1, 1, 3, 5)] == [-3, -2, -1, 1, 2, 3]
    assert div_round_away(255 * 127, 255) == 127 and div_round_away(1 * 127, 255) == 0
    assert div_round_away(2 * 127, 255) == 1 and div_round_away(128 * 127, 255) == 64
    for v in (-999, -129, -128, -1, 0, 127, 128, 999):
        assert sat_signed(v, 8) == sat_int8(v)
    assert sat_signed(40000, 16) == 32767 and sat_signed(-40000, 16) == -32768
    assert quantize_x([0, 255], 8) == [0, 127] and quantize_x([0, 255], 16) == [0, 32767]
    toy = {"weight": [[0.5, -1.0]], "bias": [0.25]}
    t8 = quantize_model(toy, 8)
    assert t8["w"] == [[64, -127]]          # 0.5·127 = 63.5 → 64 (절반 0에서 먼 쪽)
    assert t8["b"] == [round_half_away(0.25 * 127 * 127)]


def evaluate(mnist_dir, m, out_dir):
    xs = read_idx(mnist_dir / "t10k-images-idx3-ubyte")
    ys = read_idx(mnist_dir / "t10k-labels-idx1-ubyte")
    qms = {b: quantize_model(m, b) for b in (8, 16)}
    names = ("float", "int8", "int16")
    conf = {n: [[0] * N_CLASS for _ in range(N_CLASS)] for n in names}
    err = {8: [0.0, 0.0], 16: [0.0, 0.0]}     # 역양자화 Logit 오차 [최대, 합]
    rows = []
    for i, (px, y) in enumerate(zip(xs, ys)):
        zf = float_logits(px, m)
        pred = {"float": argmax_lowest(zf)}
        for b in (8, 16):
            z = int_logits(quantize_x(px, b), qms[b])
            assert all(-(1 << (ACC_W)) <= v < (1 << ACC_W) for v in z)
            pred[f"int{b}"] = argmax_lowest(z)
            scale = qms[b]["s_x"] * qms[b]["s_w"]
            e = max(abs(zq * scale - f) for zq, f in zip(z, zf))
            err[b][0] = max(err[b][0], e)
            err[b][1] += e
        for n in names:
            conf[n][y][pred[n]] += 1
        rows.append((i, y, pred["float"], pred["int8"], pred["int16"]))
    n = len(rows)
    correct = {k: sum(conf[k][c][c] for c in range(N_CLASS)) for k in names}
    agree = {
        "int8_vs_float": sum(r[3] == r[2] for r in rows),
        "int16_vs_float": sum(r[4] == r[2] for r in rows),
        "int8_vs_int16": sum(r[3] == r[4] for r in rows),
    }
    summary = {
        "test_samples": n, "correct": correct, "class_agreement": agree,
        "torch_f32_correct": m["torch_f32_test"]["correct"],
        "max_abs_logit_error": {f"int{b}": err[b][0] for b in (8, 16)},
        "mean_max_logit_error": {f"int{b}": err[b][1] / n for b in (8, 16)},
        "scale": {f"int{b}": {"s_x": qms[b]["s_x"], "s_w": qms[b]["s_w"], "max_w": qms[b]["max_w"],
                              "w_range": [min(min(r) for r in qms[b]["w"]), max(max(r) for r in qms[b]["w"])],
                              "b_q": qms[b]["b"]} for b in (8, 16)},
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    write_report(out_dir, summary, conf, rows)
    write_samples(xs, rows)
    print(f"PC_EVAL_PASS samples={n} float={correct['float']} int8={correct['int8']} "
          f"int16={correct['int16']} torch_f32={summary['torch_f32_correct']} "
          f"agree_int8_float={agree['int8_vs_float']} agree_int16_float={agree['int16_vs_float']}")


def write_report(out_dir, s, conf, rows):
    n = s["test_samples"]
    pct = lambda k: f"{100.0 * k / n:.2f}%"  # noqa: E731
    lines = ["# 4-3 MNIST 784→10 정밀도 비교 결과 (PC 실행)", "",
             "> `precision_reference.py --eval` 실제 실행 결과. RTL·Vivado 결과와 별개.", "",
             "| 모델 | 정답 수 | Accuracy | Float 대비 클래스 일치 | 최대 역양자화 Logit 오차 | 평균(표본별 최대) |",
             "|---|---:|---:|---:|---:|---:|",
             f"| Float (float32 가중치, float64 계산) | {s['correct']['float']} | {pct(s['correct']['float'])} | — | — | — |",
             f"| INT8 | {s['correct']['int8']} | {pct(s['correct']['int8'])} | "
             f"{s['class_agreement']['int8_vs_float']} ({pct(s['class_agreement']['int8_vs_float'])}) | "
             f"{s['max_abs_logit_error']['int8']:.6f} | {s['mean_max_logit_error']['int8']:.6f} |",
             f"| INT16 | {s['correct']['int16']} | {pct(s['correct']['int16'])} | "
             f"{s['class_agreement']['int16_vs_float']} ({pct(s['class_agreement']['int16_vs_float'])}) | "
             f"{s['max_abs_logit_error']['int16']:.6f} | {s['mean_max_logit_error']['int16']:.6f} |",
             "", f"- 시험셋: MNIST t10k {n}개, 전처리 `pixel/255`(세 모델 동일). PyTorch Float32 시험 정답 "
             f"{s['torch_f32_correct']}/{n}.",
             f"- INT8·INT16 클래스 일치: {s['class_agreement']['int8_vs_int16']}/{n}.", ""]
    for b in (8, 16):
        sc = s["scale"][f"int{b}"]
        lines.append(f"- INT{b}: s_x = 1/{qmax(b)}, s_w = max|W|/{qmax(b)} = {sc['s_w']:.10g} "
                     f"(max|W| = {sc['max_w']:.10g}), w_q 범위 {sc['w_range']}, zero-point 0, "
                     f"b_q = {sc['b_q']}")
    lines.append("")
    for k in ("float", "int8", "int16"):
        lines += [f"## 혼동행렬 · {k} (행 = 정답, 열 = 예측)", "",
                  "| 정답\\예측 | " + " | ".join(map(str, range(N_CLASS))) + " |",
                  "|---|" + "---:|" * N_CLASS]
        lines += [f"| {y} | " + " | ".join(map(str, conf[k][y])) + " |" for y in range(N_CLASS)]
        lines.append("")
    diff = [r for r in rows if not r[2] == r[3] == r[4]]
    lines += ["## Float·INT8·INT16 예측이 다른 시험 표본", "",
              "| index | 정답 | float | int8 | int16 |", "|---:|---:|---:|---:|---:|"]
    lines += [f"| {i} | {y} | {f} | {a} | {b} |" for i, y, f, a, b in diff]
    (out_dir / "precision_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_samples(xs, rows):
    """RTL 비교용 고정 표본: 앞 8개 + INT8≠Float 4개 + INT16≠Float 4개 + Float 오답 4개(중복 제외)."""
    pick = [r for r in rows[:8]]
    for cond in (lambda r: r[3] != r[2], lambda r: r[4] != r[2], lambda r: r[2] != r[1]):
        pick += [r for r in rows if cond(r) and r not in pick][:4]
    with SAMPLES.open("w") as f:
        f.write("# index label pred_float pred_int8 pred_int16 pixel0..783 (MNIST t10k, Yann LeCun et al.)\n")
        for i, y, pf, p8, p16 in pick:
            f.write(f"{i} {y} {pf} {p8} {p16} " + " ".join(map(str, xs[i])) + "\n")


def rtl_vectors(out, bits, m):
    selftest()
    qm = quantize_model(m, bits)
    rng = random.Random(1818)
    cases, pads, n_flip = [], [], 0
    for line in SAMPLES.read_text().splitlines():
        if line.startswith("#"):
            continue
        v = list(map(int, line.split()))
        idx, label, pf, p8, p16, px = v[0], v[1], v[2], v[3], v[4], v[5:]
        x_q = quantize_x(px, bits)
        _, scores, cls, ovf = model(x_q, qm["w"], qm["b"], ACC_W, BIAS_W, bits)
        # RTL 벡터 경로와 시험셋 평가가 같은 정수 결과를 내는지 교차 확인
        assert not ovf and scores == int_logits(x_q, qm) and cls == (p8 if bits == 8 else p16), idx
        n_flip += cls != pf
        cases.append((x_q, qm["w"], qm["b"]))
        pads.append(padding(rng, bits))
    write_vectors(out, cases, pads, ACC_W, BIAS_W, bits)
    print(f"PYTHON_PRECISION_VECTORS_PASS data_w={bits} samples={len(cases)} "
          f"class_differs_from_float={n_flip} acc_w={ACC_W} bias_w={BIAS_W} seed=1818")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--eval", action="store_true")
    p.add_argument("--mnist-dir", type=Path)
    p.add_argument("--report-dir", type=Path, default=HERE.parent / "validation")
    p.add_argument("--rtl-vectors", action="store_true")
    p.add_argument("--data-w", type=int, choices=[8, 16], default=8)
    p.add_argument("--out", type=Path)
    p.add_argument("--actual", type=Path)
    a = p.parse_args()
    mdl = json.loads(MODEL.read_text())
    if a.eval:
        selftest()
        evaluate(a.mnist_dir, mdl, a.report_dir)
    elif a.actual:
        compare(a.out, a.actual)
    else:
        rtl_vectors(a.out, a.data_w, mdl)
