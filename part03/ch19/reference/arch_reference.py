#!/usr/bin/env python3
"""PE 병렬도(1·4·8PE)·BRAM 공급 포트·메모리 구조 비교 기준모델(표준 라이브러리).

작업량은 PE 수와 무관하게 64입력×10출력 = 640 MAC(타일 1개), 784입력이면 13타일.
구성은 모두 3-2 p3_group10_core(변경 없음)로 만든다.
  PE1 = 코어 OUT_N=1 (lane 0만 유효) 10회 반복, class마다 가중치 재적재
  PE4 = 코어 OUT_N=10 (4+4+2 그룹)
  PE8 = 코어 OUT_N=6 (class 0~3, 8~9) + 코어 OUT_N=4 (class 4~7) 동시 실행, x 읽기 포트 1개 공유
        → 그룹 0에서 8 lane, 그룹 1에서 2 lane = 8PE 출력 고정(output-stationary) 스케줄
사이클 정의: start를 샘플한 에지 → done을 관측한 에지 = groups·(IN + 4) + 2
  (그룹당 CLEAR 1 + RUN IN + DRAIN 2 + CAPT 1, 시작·FINISH 2) — 3-2 코어 상태기계에서 유도.
"""
import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.host_tools.p3_integer_reference import argmax_lowest, dot_signed  # noqa: E402
from part03.ch17.reference.tile784_reference import tile_ranges  # noqa: E402
from part03.ch18.reference.precision_reference import (  # noqa: E402
    MODEL, SAMPLES, quantize_model, quantize_x,
)

IN_LEN, N_CLASS = 64, 10
GROUP_OVERHEAD, RUN_OVERHEAD = 4, 2
# PE8 분할: (코어, 코어 내부 class) ← 전역 class
PE8_MAP = {c: ("A", c) for c in range(4)}
PE8_MAP.update({c: ("B", c - 4) for c in range(4, 8)})
PE8_MAP.update({8: ("A", 4), 9: ("A", 5)})


def issue_lower_bound(macs, pe):
    """이론 하한: MAC을 모든 PE에 완벽히 나눈 발행 클록(메모리·제어 지연 없음)."""
    return math.ceil(macs / pe)


def groups(out_n, pe):
    return math.ceil(out_n / pe)


def schedule_issue(in_len, out_n, pe):
    """출력 고정 그룹 스케줄의 발행 클록: 그룹마다 IN개 입력을 모든 lane에 방송."""
    return groups(out_n, pe) * in_len


def core_cycles(in_len, n_groups):
    return n_groups * (in_len + GROUP_OVERHEAD) + RUN_OVERHEAD


def stall_issue(in_len, out_n, pe, w_ports):
    """가중치 읽기 포트가 w_ports개(각 1단어/클록)일 때 발행 클록. x는 1단어 방송으로 충분."""
    total = 0
    for g in range(groups(out_n, pe)):
        active = min(pe, out_n - g * pe)
        total += in_len * math.ceil(active / w_ports)
    return total


def config_cycles():
    """RTL에서 측정할 구성별 기대 사이클(타일 1개)."""
    pe1_pass = core_cycles(IN_LEN, groups(1, 4))
    pe8a, pe8b = core_cycles(IN_LEN, groups(6, 4)), core_cycles(IN_LEN, groups(4, 4))
    return {"PE1_pass": pe1_pass, "PE1": N_CLASS * pe1_pass,
            "PE4": core_cycles(IN_LEN, groups(N_CLASS, 4)),
            "PE8A": pe8a, "PE8B": pe8b, "PE8": max(pe8a, pe8b),
            "LOAD_W": N_CLASS * IN_LEN}


def selftest():
    macs = IN_LEN * N_CLASS
    assert [issue_lower_bound(macs, p) for p in (1, 4, 8)] == [640, 160, 80]
    assert [schedule_issue(IN_LEN, N_CLASS, p) for p in (1, 4, 8)] == [640, 192, 128]
    cc = config_cycles()
    assert cc["PE4"] == 206                       # 3-2 측정값과 같은 식
    assert core_cycles(8, 3) == 38 and core_cycles(64, 2) == 138   # 3-4 2층·1층 측정값
    assert cc["PE8"] == core_cycles(IN_LEN, groups(N_CLASS, 8))     # 두 코어 = 8PE 스케줄
    assert stall_issue(IN_LEN, N_CLASS, 8, 8) == 128 and stall_issue(IN_LEN, N_CLASS, 8, 2) == 320
    assert stall_issue(IN_LEN, N_CLASS, 4, 4) == 192 and stall_issue(IN_LEN, N_CLASS, 1, 1) == 640
    assert sorted(PE8_MAP) == list(range(N_CLASS))
    return cc


def load_runs(n_samples):
    m = json.loads(MODEL.read_text())
    qm = quantize_model(m, 8)
    runs, samples = [], []
    for line in SAMPLES.read_text().splitlines():
        if line.startswith("#"):
            continue
        v = list(map(int, line.split()))
        samples.append((v[0], v[3], quantize_x(v[5:], 8)))     # index, INT8 예측, x_q
        if len(samples) == n_samples:
            break
    for si, (idx, _, x) in enumerate(samples):
        for t, (s, n) in enumerate(tile_ranges()):
            xt = x[s:s + n] + [0] * (IN_LEN - n)
            wt = [qm["w"][c][s:s + n] + [0] * (IN_LEN - n) for c in range(N_CLASS)]
            runs.append((si, t, xt, wt))
    return qm, samples, runs


def generate(out, n_samples):
    cc = selftest()
    _, samples, runs = load_runs(n_samples)
    with (out / "vectors.txt").open("w") as vf, (out / "expected.txt").open("w") as ef:
        vf.write(f"{len(runs)}\n")
        for r, (_, _, xt, wt) in enumerate(runs):
            vf.write(" ".join(map(str, xt)) + "\n")
            for row in wt:
                vf.write(" ".join(map(str, row)) + "\n")
            part = " ".join(str(dot_signed(xt, row)) for row in wt)
            for cfg in ("PE1", "PE4", "PE8"):
                ef.write(f"R{r} {cfg} {part}\n")
        ef.write(" ".join(f"{k}={cc[k]}" for k in ("PE1_pass", "PE1", "PE4", "PE8A", "PE8B", "PE8"))
                 + f" LOAD_W_PE1={cc['LOAD_W']} LOAD_W_PE4={cc['LOAD_W']} LOAD_W_PE8={cc['LOAD_W']}\n")
    print(f"PYTHON_ARCH_SELF_TEST_PASS samples={len(samples)} tile_runs={len(runs)} "
          f"cycles PE1={cc['PE1']} PE4={cc['PE4']} PE8={cc['PE8']} load_w={cc['LOAD_W']}")


def compare(out, actual, n_samples):
    exp = (out / "expected.txt").read_text().splitlines()
    got = actual.read_text().splitlines()
    if exp != got:
        for i, (e, g) in enumerate(zip(exp, got)):
            if e != g:
                print(f"FAIL line {i}:\n  expected={e}\n  got     ={g}")
                break
        print(f"lines expected={len(exp)} got={len(got)}")
        raise SystemExit("PYTHON_RTL_COMPARE_FAIL")
    # RTL 타일 부분합(PE4 줄)을 13타일 합 + Bias → 4-3 INT8 평가의 Class와 같아야 한다
    qm, samples, runs = load_runs(n_samples)
    sums = [[0] * N_CLASS for _ in samples]
    for line in got:
        f = line.split()
        if len(f) == 12 and f[1] == "PE4":
            r = int(f[0][1:])
            for c in range(N_CLASS):
                sums[runs[r][0]][c] += int(f[2 + c])
    for (idx, pred8, _), acc in zip(samples, sums):
        cls = argmax_lowest([a + b for a, b in zip(acc, qm["b"])])
        if cls != pred8:
            raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL class sample {idx}: rtl={cls} eval={pred8}")
    print(f"PYTHON_RTL_COMPARE_PASS tile_runs={len(runs)} configs=PE1,PE4,PE8 partials_bit_exact=1 "
          f"cycles_match_model=1 mnist_samples={len(samples)} class_match_ch18_int8=1")


def report():
    """구성별 사이클·포트 표(Markdown). 시뮬레이션 사이클 모델이며 실측 시간이 아니다."""
    macs, cc = IN_LEN * N_CLASS, selftest()
    tiles = len(tile_ranges())
    print("| PE | 이론 하한(640 MAC) | 그룹 스케줄 발행 | lane 이용률 | 코어 사이클(타일 1개) | "
          "784 추론 연산 사이클(13타일) | 가중치 읽기 포트 |")
    print("|---:|---:|---:|---:|---:|---:|---:|")
    for pe, key in ((1, "PE1"), (4, "PE4"), (8, "PE8")):
        issue = schedule_issue(IN_LEN, N_CLASS, pe)
        print(f"| {pe} | {issue_lower_bound(macs, pe)} | {issue} | {100 * macs / (pe * issue):.1f}% | "
              f"{cc[key]} | {tiles * cc[key]} | {pe} |")
    print("\n가중치 읽기 포트 수에 따른 발행 클록(타일 1개, x 방송 1포트):\n")
    print("| PE \\ 포트 | 1 | 2 | 4 | 8 |")
    print("|---:|---:|---:|---:|---:|")
    for pe in (1, 4, 8):
        print(f"| {pe} | " + " | ".join(str(stall_issue(IN_LEN, N_CLASS, pe, p)) for p in (1, 2, 4, 8)) + " |")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", type=Path)
    p.add_argument("--actual", type=Path)
    p.add_argument("--samples", type=int, default=4)
    p.add_argument("--report", action="store_true")
    a = p.parse_args()
    if a.report:
        report()
    elif a.actual:
        compare(a.out, a.actual, a.samples)
    else:
        generate(a.out, a.samples)
