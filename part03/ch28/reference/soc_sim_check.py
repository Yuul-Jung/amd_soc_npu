#!/usr/bin/env python3
"""28장 SoC 전체 xsim 입력 생성·판정.

--make  : 표본 0(digit_samples.txt 첫 줄)을 img_id 0x28로 프레임화 → 한 줄 1바이트 16진 파일, 기대값 JSON
--check : TB 기록(UART 줄, LED 핀, FND 자리별 an/seg/dp)을 Python 골든과 비교
  부팅: READY(model=MODEL_ID, model_ok=1, bias_rc=0), DISP = fnd_boot, FND 핀 = 모델 ID 상위 16비트
  추론: RESULT(match=1, 점수 10개 = 골든, class = 골든), DISP = fnd_result, LED 핀, FND 핀(자리 1 꺼짐)
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch18.reference.precision_reference import quantize_x  # noqa: E402
from part03.ch28.reference.digit_reference import (  # noqa: E402
    fnd_boot, fnd_result, fnd_segments, golden, infer_frame, load_qmodel, model_id, parse_kv, read_samples,
)

IMG_ID = 0x28


def make(frame_out, exp_out):
    qm = load_qmodel()
    s = read_samples()[0]
    x = quantize_x(s["pixels"], 8)
    scores, cls = golden(x, qm)
    f = infer_frame(IMG_ID, model_id(qm), x)
    frame_out.write_text("".join(f"{b:02x}\n" for b in f))
    exp_out.write_text(json.dumps({"img_id": IMG_ID, "index": s["index"], "label": s["label"], "class": cls,
                                   "scores": scores, "model_id": model_id(qm)}))
    print(f"SOC_FRAME bytes={len(f)} index={s['index']} label={s['label']} golden_class={cls}")


def fnd_block(lines):
    out = {}
    for l in lines:
        kv = parse_kv(l)
        if l.startswith("FND") and "off" not in l:
            out[int(kv["digit"])] = (int(kv["an"], 2), int(kv["seg"], 16), int(kv["dp"]))
        elif l.startswith("FND"):
            out[int(kv["digit"])] = None
    return out


def check_fnd(name, block, word, results):
    for d in range(4):
        an, seg, dp = fnd_segments(word, d)
        exp = None if an == 0xF else (an, seg, dp)
        results.append((f"{name}_fnd_digit{d}", block.get(d) == exp, f"pin={block.get(d)} expect={exp}"))


def hx(v):
    """(변경) xil_printf는 %x를 대문자로, PC printf는 소문자로 찍는다. 문자열 대신 정수로 비교한다."""
    try:
        return int(v, 16)
    except (TypeError, ValueError):
        return None


def check(rec, exp_path):
    e = json.loads(exp_path.read_text())
    raw = [l.replace("\x00", "").strip() for l in rec.read_text(errors="replace").splitlines()]
    uart = [l[5:].strip() for l in raw if l.startswith("UART ")]
    boot_end = raw.index(next(l for l in raw if l.startswith("SEND")))
    resp_start = raw.index(next(l for l in raw if l.startswith("RESPONSE_DONE")))
    boot_fnd = fnd_block(raw[:boot_end])
    resp_fnd = fnd_block(raw[resp_start:])
    led = [int(parse_kv(l)["led"], 16) for l in raw if l.startswith("PIN")]
    results = []
    ready = parse_kv(uart[0]) if uart and uart[0].startswith("P3_DIGIT READY") else {}
    results.append(("ready_line", hx(ready.get("model")) == e["model_id"] and ready.get("model_ok") == "1"
                    and ready.get("bias_rc") == "0", uart[0] if uart else None))
    bw, bl = fnd_boot(e["model_id"])
    d0 = parse_kv(uart[1]) if len(uart) > 1 else {}
    results.append(("boot_disp", hx(d0.get("fnd")) == bw and hx(d0.get("led")) == bl, uart[1:2]))
    check_fnd("boot", boot_fnd, bw, results)
    results.append(("boot_led_pin", led[:1] == [bl], led[:1]))
    r = parse_kv(uart[2]) if len(uart) > 2 else {}
    scores = [int(v) for v in r.get("scores", "").split(",") if v]
    results.append(("result_line", uart[2].startswith("RESULT") and r.get("match") == "1" and r.get("rc") == "0"
                    and int(r.get("img", -1)) == e["img_id"] and int(r.get("npu_class", -1)) == e["class"]
                    and int(r.get("cpu_class", -1)) == e["class"] and hx(r.get("model")) == e["model_id"],
                    uart[2] if len(uart) > 2 else None))
    results.append(("scores_eq_golden", scores == e["scores"], f"{scores} vs {e['scores']}"))
    rw, rl = fnd_result(e["img_id"], e["class"])
    d1 = parse_kv(uart[3]) if len(uart) > 3 else {}
    results.append(("result_disp", hx(d1.get("fnd")) == rw and hx(d1.get("led")) == rl, uart[3:4]))
    check_fnd("result", resp_fnd, rw, results)
    results.append(("result_led_pin", led[1:2] == [rl], led[1:2]))
    for name, ok, info in results:
        print(f"SOCCHK {name} {'PASS' if ok else 'FAIL'} :: {info}")
    t = {l.split()[0]: int(parse_kv(l)["t_ns"]) for l in raw if "t_ns=" in l}
    print(f"SOC_TIMELINE boot_done_ms={t['BOOT_DONE'] / 1e6:.3f} send_start_ms={t['SEND'] / 1e6:.3f} "
          f"response_done_ms={t['RESPONSE_DONE'] / 1e6:.3f} end_ms={t['SOC28_SIM_END'] / 1e6:.3f}")
    ok = all(ok for _, ok, _ in results)
    print(f"SOC28_RTL_SIM_{'PASS' if ok else 'FAIL'} checks={sum(o for _, o, _ in results)}/{len(results)}")
    return 0 if ok else 1


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--make", nargs=2, type=Path, metavar=("FRAME_HEX", "EXPECT_JSON"))
    p.add_argument("--check", nargs=2, type=Path, metavar=("TB_RECORD", "EXPECT_JSON"))
    a = p.parse_args()
    if a.make:
        make(*a.make)
    if a.check:
        return check(*a.check)
    return 0


if __name__ == "__main__":
    sys.exit(main())
