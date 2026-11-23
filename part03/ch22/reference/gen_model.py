#!/usr/bin/env python3
"""4-3 INT8 양자화 모델과 MNIST 표본 4개로 C 헤더(model_data.h)를 만든다(빌드 산출물, 저장소 미포함).

기대 점수·Class는 4-2 기준모델 model()로 계산해 헤더에 넣는다(C 응용이 NPU·CPU 결과와 비교).
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch17.reference.tile784_reference import model  # noqa: E402
from part03.ch18.reference.precision_reference import (  # noqa: E402
    MODEL, SAMPLES, quantize_model, quantize_x,
)

N_SAMPLES = 4


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    qm = quantize_model(json.loads(MODEL.read_text()), 8)
    rows = [list(map(int, l.split())) for l in SAMPLES.read_text().splitlines() if not l.startswith("#")]
    picked = rows[:2] + [r for r in rows if r[3] != r[2]][:1] + [r for r in rows if r[2] != r[1]][:1]
    lines = ["/* 자동 생성: part03/ch22/reference/gen_model.py (4-3 INT8 모델, MNIST t10k 표본) */",
             "#ifndef MODEL_DATA_H", "#define MODEL_DATA_H", "#include <stdint.h>",
             f"#define MODEL_N_SAMPLES {len(picked)}",
             "static const int8_t model_w[10][784] = {"]
    lines += ["  {" + ",".join(map(str, row)) + "}," for row in qm["w"]]
    lines += ["};", "static const int64_t model_b[10] = {" + ",".join(f"{v}LL" for v in qm["b"]) + "};",
              f"static const int8_t sample_x[{len(picked)}][784] = {{"]
    exp = []
    for r in picked:
        x = quantize_x(r[5:], 8)
        _, scores, cls, ovf = model(x, qm["w"], qm["b"], 41, 40, 8)
        assert not ovf and cls == r[3]
        exp.append((r[0], r[1], cls, scores))
        lines.append("  {" + ",".join(map(str, x)) + "},")
    lines += ["};",
              "static const int sample_index[] = {" + ",".join(str(e[0]) for e in exp) + "};",
              "static const int sample_label[] = {" + ",".join(str(e[1]) for e in exp) + "};",
              "static const int sample_class[] = {" + ",".join(str(e[2]) for e in exp) + "};",
              "static const int64_t sample_scores[][10] = {"]
    lines += ["  {" + ",".join(f"{v}LL" for v in e[3]) + "}," for e in exp]
    lines += ["};", "#endif", ""]
    a.out.write_text("\n".join(lines))
    print(f"MODEL_HEADER_DONE samples={len(picked)} classes={[e[2] for e in exp]} labels={[e[1] for e in exp]}")


if __name__ == "__main__":
    main()
