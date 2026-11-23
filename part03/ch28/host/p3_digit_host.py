#!/usr/bin/env python3
"""PC 호스트: 손글씨 숫자 이미지 → 784 INT8 전처리 → UART 프레임 → 보드(또는 PC 시뮬레이션) 결과 → CSV.

전송 경로(같은 규약, reference/digit_reference.py 머리말):
  --port /dev/ttyUSBx   실제 Basys3(USB-UART 115200 8N1, pyserial)             → target=fpga
  --cosim "<명령>"       PC용으로 빌드한 같은 펌웨어 + NPU RTL(표준 입출력) → target=rtl_cosim
입력:  --samples(기본: reference/digit_samples.txt), --mnist-dir D --indices 0,1,..., --images a.png ...(28×28)
CSV:   target,img_id,source,index,label,golden_class,cpu_class,dev_class,scores_match,display_ok,rc,category
  category: OK / MODEL_MISCLASS(골든 = 장치, 하지만 정답과 다름: 모델 한계) / HW_MISMATCH(장치 ≠ 골든)
            / CPU_NPU_MISMATCH / DEVICE_ERROR(ERROR 응답) / NO_RESPONSE
--error-suite: CRC·모델 ID·화소 범위·명령·잡음 바이트·짧은 프레임·가중치 미적재 자체 시험과 복구를 시험한다.
골든(PC 정수 모델)과 장치 결과는 서로 다른 근거로 기록한다. 정확도도 둘을 따로 센다.
"""
import argparse
import csv
import shlex
import struct
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch18.reference.precision_reference import quantize_x, read_idx  # noqa: E402
from part03.ch28.reference.digit_reference import (  # noqa: E402
    CMD_ID, CMD_SELFTEST, ERR, frame, fnd_error, fnd_result, golden, infer_frame, load_image,
    load_qmodel, model_id, parse_kv, read_samples,
)


class ProcTransport:
    """PC 시뮬레이션: 펌웨어 프로세스의 표준 입출력."""

    def __init__(self, cmd):
        import selectors
        self.p = subprocess.Popen(shlex.split(cmd), stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.sel = selectors.DefaultSelector()
        self.sel.register(self.p.stdout, selectors.EVENT_READ)
        self.buf = b""

    def write(self, data):
        self.p.stdin.write(data)
        self.p.stdin.flush()

    def readline(self, timeout):
        end = time.monotonic() + timeout
        while b"\n" not in self.buf:
            left = end - time.monotonic()
            if left <= 0 or not self.sel.select(left):
                return None
            chunk = self.p.stdout.read1(4096)
            if not chunk:
                return None
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return line.decode(errors="replace").strip()

    def close(self):
        self.p.stdin.close()
        return self.p.wait(timeout=600)


class SerialTransport:
    def __init__(self, port, baud):
        import serial
        self.s = serial.Serial(port, baud, bytesize=8, parity="N", stopbits=1, timeout=0.1)
        self.buf = b""

    def write(self, data):
        self.s.write(data)
        self.s.flush()

    def readline(self, timeout):
        end = time.monotonic() + timeout
        while b"\n" not in self.buf:
            if time.monotonic() > end:
                return None
            self.buf += self.s.read(256)
        line, self.buf = self.buf.split(b"\n", 1)
        return line.decode(errors="replace").strip()

    def close(self):
        self.s.close()
        return 0


class Host:
    def __init__(self, tr, timeout, log):
        self.tr, self.timeout, self.log = tr, timeout, log

    def transact(self, data):
        """응답 규칙: 식별(P3_DIGIT)은 한 줄, 나머지는 주 줄(RESULT/ERROR/SELFTEST, 불일치면 RESULT 뒤 ERROR) + DISP 한 줄."""
        if data:
            self.tr.write(data)
        main = None
        while True:
            line = self.tr.readline(self.timeout)
            if line is None:
                return main, None
            self.log.write(line + "\n")
            if line.startswith("P3_DIGIT") and main is None:
                return line, None
            if line.startswith("DISP"):
                return main, parse_kv(line)
            if main is None:
                main = line


def hexint(s):
    return int(s, 16)


def collect_images(a):
    items = []
    if a.images:
        for i, p in enumerate(a.images):
            items.append({"source": Path(p).name, "index": i, "label": -1, "pixels": load_image(p, a.invert)})
    elif a.mnist_dir:
        xs = read_idx(a.mnist_dir / "t10k-images-idx3-ubyte")
        ys = read_idx(a.mnist_dir / "t10k-labels-idx1-ubyte")
        idx = [int(v) for v in a.indices.split(",")] if a.indices else range(len(ys))
        items = [{"source": "t10k", "index": i, "label": ys[i], "pixels": xs[i]} for i in idx]
    else:
        items = [dict(r, source="digit_samples") for r in read_samples()]
    return items[: a.limit] if a.limit else items


def run_images(h, items, qm, mid, target, writer):
    stats = dict(n=0, ok=0, golden_correct=0, dev_correct=0, dev_golden=0, scores=0, display=0, labeled=0)
    for img_id, it in enumerate(items):
        x = quantize_x(it["pixels"], 8)
        gs, gc = golden(x, qm)
        main, disp = h.transact(infer_frame(img_id, mid, x))
        row = dict(target=target, img_id=img_id, source=it["source"], index=it["index"], label=it["label"],
                   golden_class=gc, cpu_class="", dev_class="", scores_match=0, display_ok=0, rc="", category="")
        if main is None:
            row["category"] = "NO_RESPONSE"
        elif main.startswith("ERROR"):
            row["category"], row["rc"] = "DEVICE_ERROR", parse_kv(main).get("name")
        else:
            kv = parse_kv(main)
            dev, cpu = int(kv["npu_class"]), int(kv["cpu_class"])
            scores = [int(v) for v in kv["scores"].split(",")]
            row.update(cpu_class=cpu, dev_class=dev, rc=kv["rc"], scores_match=int(scores == gs and dev == gc))
            exp = fnd_result(img_id, dev)
            row["display_ok"] = int(disp is not None and (hexint(disp["fnd"]), hexint(disp["led"])) == exp)
            if kv["match"] != "1":
                row["category"] = "CPU_NPU_MISMATCH"
            elif not row["scores_match"]:
                row["category"] = "HW_MISMATCH"
            elif it["label"] >= 0 and dev != it["label"]:
                row["category"] = "MODEL_MISCLASS"
            else:
                row["category"] = "OK"
            stats["scores"] += row["scores_match"]
            stats["display"] += row["display_ok"]
            stats["dev_golden"] += int(dev == gc)
            if it["label"] >= 0:
                stats["dev_correct"] += int(dev == it["label"])
        if it["label"] >= 0:
            stats["labeled"] += 1
            stats["golden_correct"] += int(gc == it["label"])
        stats["n"] += 1
        stats["ok"] += int(row["category"] in ("OK", "MODEL_MISCLASS"))
        writer.writerow(row)
        print(f"IMG {img_id:3d} {it['source']}#{it['index']} label={it['label']} golden={gc} "
              f"dev={row['dev_class']} scores_match={row['scores_match']} display_ok={row['display_ok']} {row['category']}")
    return stats


def error_suite(h, qm, mid, slow):
    """반환: (통과 수, 시험 수). 각 시험은 기대 응답·표시 값을 확인한다."""
    x = quantize_x(read_samples()[0]["pixels"], 8)
    good = infer_frame(7, mid, x)
    gs, gc = golden(x, qm)
    results = []

    def expect_error(name, data, code, img=-1, wait=0.0, junk=None):
        if wait:
            h.tr.write(data)
            time.sleep(wait)
            main, disp = h.transact(b"")
        else:
            main, disp = h.transact(data)
        kv = parse_kv(main or "")
        ok = bool(main and main.startswith("ERROR") and int(kv.get("code", -9)) == code
                  and int(kv.get("img", -9)) == img and disp is not None
                  and (hexint(disp["fnd"]), hexint(disp["led"])) == fnd_error(img, code)
                  and (junk is None or int(kv.get("junk", -1)) == junk))
        results.append((name, ok, main))

    def expect_result(name, data, junk=0):
        main, disp = h.transact(data)
        kv = parse_kv(main or "")
        ok = bool(main and main.startswith("RESULT") and kv.get("match") == "1"
                  and [int(v) for v in kv["scores"].split(",")] == gs and int(kv["npu_class"]) == gc
                  and disp is not None and (hexint(disp["fnd"]), hexint(disp["led"])) == fnd_result(7, gc))
        ok = ok and int(kv.get("junk", -1)) == junk
        results.append((name, ok, main))

    bad_crc = bytearray(good)
    bad_crc[100] ^= 0x01
    expect_error("crc_flip", bytes(bad_crc), ERR["CRC"])
    expect_error("model_id", infer_frame(7, mid ^ 1, x), ERR["MODEL"], img=7)
    bad_px = list(x)
    bad_px[300] = -1                                   # 0x80..0xFF = 음수 → 전처리 계약(0..127) 위반
    expect_error("pixel_range", infer_frame(7, mid, bad_px), ERR["RANGE"], img=7)
    expect_error("unknown_cmd", frame(b"Z", b"\x00\x01"), ERR["CMD"])
    expect_error("junk_then_bad_cmd", b"\x00\xffxyP" + frame(b"Z"), ERR["CMD"], junk=5)
    expect_result("junk_then_good", b"\x55\xaaP4" + good, junk=4)
    expect_error("short_frame", good[:400], ERR["TIMEOUT"], wait=slow)
    expect_result("after_timeout_good", good)
    main, disp = h.transact(frame(CMD_SELFTEST))
    kv = parse_kv(main or "")
    results.append(("w_missing_selftest", bool(main and main.startswith("SELFTEST") and kv.get("err_code") == "9"
                                               and kv.get("recovered") == "1" and disp is not None
                                               and hexint(disp["fnd"]) == 0x30000), main))
    expect_result("after_selftest_good", good)
    main, _ = h.transact(frame(CMD_ID))
    kv = parse_kv(main or "")
    results.append(("identify", bool(main and main.startswith("P3_DIGIT") and hexint(kv.get("model", "0")) == mid
                                     and kv.get("model_ok") == "1"), main))
    for name, ok, main in results:
        print(f"ERRCASE {name} {'PASS' if ok else 'FAIL'} :: {main}")
    return sum(ok for _, ok, _ in results), len(results)


def main():
    p = argparse.ArgumentParser()
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--port")
    g.add_argument("--cosim")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--timeout", type=float, default=30.0, help="응답 줄 대기(초)")
    p.add_argument("--short-wait", type=float, default=None, help="짧은 프레임 뒤 대기(초, 펌웨어 바이트 간격 제한보다 길게)")
    p.add_argument("--images", nargs="*")
    p.add_argument("--invert", action="store_true", help="검은 글씨·흰 바탕 이미지를 MNIST 극성으로 뒤집음")
    p.add_argument("--mnist-dir", type=Path)
    p.add_argument("--indices")
    p.add_argument("--limit", type=int)
    p.add_argument("--error-suite", action="store_true")
    p.add_argument("--csv", type=Path, required=True)
    p.add_argument("--log", type=Path, required=True, help="장치가 보낸 UART 줄 원문")
    a = p.parse_args()
    target = "fpga" if a.port else "rtl_cosim"
    tr = SerialTransport(a.port, a.baud) if a.port else ProcTransport(a.cosim)
    qm = load_qmodel()
    mid = model_id(qm)
    with a.log.open("w") as log, a.csv.open("w", newline="") as f:
        h = Host(tr, a.timeout, log)
        if a.cosim:                                    # 부팅 줄 2개(READY, DISP)를 먼저 받는다
            for _ in range(2):
                log.write(f"{tr.readline(a.timeout)}\n")
        else:                                          # 보드는 이미 부팅했을 수 있다: 남은 수신 버퍼를 비운다
            tr.s.reset_input_buffer()
        main, _ = h.transact(frame(CMD_ID))
        kv = parse_kv(main or "")
        if not main or hexint(kv.get("model", "0")) != mid or kv.get("model_ok") != "1":
            print(f"DIGIT_HOST_FAIL model_id host={mid:08x} device={main}")
            return 1
        print(f"MODEL_ID host={mid:08x} device={kv['model']} model_ok={kv['model_ok']}")
        w = csv.DictWriter(f, fieldnames=["target", "img_id", "source", "index", "label", "golden_class", "cpu_class",
                                          "dev_class", "scores_match", "display_ok", "rc", "category"])
        w.writeheader()
        st = run_images(h, collect_images(a), qm, mid, target, w)
        err_pass = err_n = 0
        if a.error_suite:
            err_pass, err_n = error_suite(h, qm, mid, a.short_wait if a.short_wait else (1.0 if a.cosim else 5.0))
    rc = tr.close()
    lab = max(st["labeled"], 1)
    print(f"DIGIT_HOST_SUMMARY target={target} images={st['n']} scores_match={st['scores']} "
          f"device_eq_golden={st['dev_golden']} display_ok={st['display']} "
          f"golden_label_acc={st['golden_correct']}/{st['labeled']} ({100 * st['golden_correct'] / lab:.1f}%) "
          f"device_label_acc={st['dev_correct']}/{st['labeled']} ({100 * st['dev_correct'] / lab:.1f}%) "
          f"error_suite={err_pass}/{err_n} proc_rc={rc}")
    ok = st["scores"] == st["n"] == st["display"] == st["dev_golden"] and err_pass == err_n and rc == 0
    print("DIGIT_HOST_PASS" if ok else "DIGIT_HOST_FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
