#!/usr/bin/env python3
"""센서 융합 상태 감시 기준모델(정본, 표준 라이브러리만). 교육용 합성 데이터이며 산업 안전 보증이 아니다.

센서 3종(제2부 IP 기준, 창 8표본·100 ms 간격):
  온도  DS18B20  int16, 1/16 °C   결측 0x7FFF   유효 -20.0..100.0 °C (-320..1600)
  진동  XADC     u16 12비트 코드  결측 0xFFFF   유효 0..4095, 창 전체가 ≤15 또는 ≥4080이면 고착(단선·단락)
  거리  HC-SR04  u16 cm           결측 0xFFFF   유효 2..400 cm (Echo 시간 초과 = 결측)
  age_ms: 센서 노드가 측정한 뒤 지난 시간(센서별). 500 ms 초과 = 지연(stale)

판정 순서(AI보다 규칙이 먼저, guard):
  센서별 범위 밖·고착 → FAULT 비트(온도 1, 진동 2, 거리 4) / 결측·지연 → UNKNOWN 비트(같은 위치)
  FAULT 비트가 하나라도 있으면 후보 FAULT, 아니면 UNKNOWN 비트가 있으면 후보 UNKNOWN. 이때 NPU는 실행하지 않는다.
  모두 유효할 때만 특징 6개 → NPU(5-1 IP, 0번 타일만 사용) → 후보 = NPU class(0 NORMAL, 1 WARNING, 2 FAULT)
  링크: 프레임 대기 시간 초과 또는 연속 프로토콜 오류 3회 → 후보 UNKNOWN(이유 비트 8). NPU 오류·CPU 불일치도 UNKNOWN.

특징 6개(센서별로 따로 정한 심각도 눈금, 단위를 섞지 않는다). q(n, d) = min(127, max(0, n)·127 // d)
  각 눈금: 0 = 정상 상한, 약 64 = WARNING/FAULT 경계(교육용 가정), 127 = 명백한 FAULT
  f0 온도 최고    q(max t - 720, 800)          45 °C → 0, 70 °C → 63, 95 °C → 127   (t: 1/16 °C)
  f1 온도 상승    q((t7 - t0) - 16, 160)       창(0.7 s) 안 1 °C → 0, 6 °C → 63, 11 °C → 127
  f2 진동 p-p     q((max v - min v) - 400, 2200)
  f3 진동 MAD     q(Σ|v - mean v| // 8 - 120, 760),  mean v = Σv // 8 (0 이상이라 C와 같다)
  f4 거리 근접    q(125 - min d, 160)           125 cm → 0, 45 cm → 63
  f5 접근 속도    q((d0 - d7) - 10, 120)        창 안 10 cm → 0, 70 cm → 63

NPU 모델: 학습(float, train_sensor_model.py) → 4-3 quantize_model(…, 8) → w[3][6]·b[3]
  5-1 IP는 784 입력·10 class 고정 → x[0..5] = 특징, x[6..783] = 0, w 행 3..9 = 0, b[3..9] = UNUSED_BIAS(-2^38)
  MODEL_ID = zlib.crc32(w[10][784] 바이트 ‖ b[10] int64 LE) (6-1과 같은 규칙)

경보 정책(상태 코드 NORMAL 0, WARNING 1, FAULT 2, UNKNOWN 3, 심각도 NORMAL < WARNING < UNKNOWN < FAULT):
  Reset·부팅 = UNKNOWN. 후보 심각도 ≥ 현재 → 즉시 그 상태(cnt 0), 후보가 FAULT면 latch = 1
  후보 < 현재: latch면 cnt 0(진행 없음), 아니면 연속 CLEAR_N(3)번째에 그 3개 중 가장 심각한 상태로 내림
  ACK: latch면 latch 0·cnt 0(ok=1), 아니면 무시(ok=0). 같은 클록에 후보와 ACK가 오면(RTL) ACK는 무시한다(보수적)

UART 프레임: 6-1과 같은 'P' '3' CMD PAYLOAD CRC16(CCITT-FALSE, 상위 먼저)
  'I' 식별 → P3_SENSOR READY …     'A' ACK → ACK ok=… state=… latch=…
  'S' seq u16 ‖ model_id u32 ‖ age_t,age_v,age_d u16 ‖ 8 × (t i16, v u16, d u16)  (모두 LE, 60바이트)
      → STATE src=FRAME … (guard·특징·점수·후보·상태)
  응답은 항상 DISP fnd=… led=… 로 끝난다(보드 GPIO에 쓴 값).
"""
import argparse
import json
import math
import random
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch17.reference.tile784_reference import model  # noqa: E402
from part03.ch18.reference.precision_reference import quantize_model  # noqa: E402
from part03.ch28.reference.digit_reference import crc16, fnd_segments, parse_kv  # noqa: E402,F401

HERE = Path(__file__).resolve().parent
MODEL_JSON = HERE / "sensor_model_f32.json"
N_WIN, N_FEAT, N_CLS, N_IN, N_CLASS = 8, 6, 3, 784, 10
NORMAL, WARNING, FAULT, UNKNOWN = 0, 1, 2, 3
NAMES = ["NORMAL", "WARNING", "FAULT", "UNKNOWN"]
SEV = {NORMAL: 0, WARNING: 1, UNKNOWN: 2, FAULT: 3}
CODE_OF_SEV = {v: k for k, v in SEV.items()}
CLEAR_N = 3
LINK_BAD_N = 3
STALE_MS = 500
T_MISS, V_MISS, D_MISS = 0x7FFF, 0xFFFF, 0xFFFF
T_MIN, T_MAX = -320, 1600
V_MAX, V_STUCK_LO, V_STUCK_HI = 4095, 15, 4080
D_MIN, D_MAX = 2, 400
B_T, B_V, B_D, B_LINK = 1, 2, 4, 8
UNUSED_BIAS = -(1 << 38)
SYNC = b"P3"
CMD_ID, CMD_SENSOR, CMD_ACK = b"I", b"S", b"A"
PAYLOAD_BYTES = 2 + 4 + 6 + N_WIN * 6
ERR = {"CRC": 1, "TIMEOUT": 2, "CMD": 3, "MODEL": 4, "NPU": 6, "MISMATCH": 7}
FND_ON_SHIFT, FND_DP_SHIFT = 16, 20
LED_LATCH, LED_ERROR, LED_ALARM = 1 << 13, 1 << 14, 1 << 15


# ---------------------------------------------------------------- guard·특징
def guard(s):
    """s = dict(age=[t,v,d], t=[8], v=[8], d=[8]) → (fmask, umask)."""
    fmask = umask = 0
    for bit, age in zip((B_T, B_V, B_D), s["age"]):
        if age > STALE_MS:
            umask |= bit
    if any(t == T_MISS for t in s["t"]):
        umask |= B_T
    elif any(t < T_MIN or t > T_MAX for t in s["t"]):
        fmask |= B_T
    if any(v == V_MISS for v in s["v"]):
        umask |= B_V
    elif any(v > V_MAX for v in s["v"]) or all(v <= V_STUCK_LO for v in s["v"]) or all(v >= V_STUCK_HI for v in s["v"]):
        fmask |= B_V
    if any(d == D_MISS for d in s["d"]):
        umask |= B_D
    elif any(d < D_MIN or d > D_MAX for d in s["d"]):
        fmask |= B_D
    return fmask, umask


def q(n, d):
    return min(127, max(0, n) * 127 // d)


def features(s):
    t, v, d = s["t"], s["v"], s["d"]
    mv = sum(v) // N_WIN
    return [q(max(t) - 720, 800), q(t[-1] - t[0] - 16, 160),
            q(max(v) - min(v) - 400, 2200), q(sum(abs(e - mv) for e in v) // N_WIN - 120, 760),
            q(125 - min(d), 160), q(d[0] - d[-1] - 10, 120)]


# ---------------------------------------------------------------- 합성 데이터(교육용)
def gen_window(rng, label):
    t0, dt, amp, d0, spd = rng.uniform(20, 45), rng.uniform(-0.05, 0.08), rng.uniform(10, 180), rng.uniform(130, 395), 0.0
    kinds = ["temp", "rise", "vib", "dist", "approach"]
    picks = [rng.choice(kinds)] if label else []
    if label and rng.random() < 0.3:
        picks.append(rng.choice(kinds))
    for k in picks:
        w = label == WARNING
        if k == "temp":
            t0 = rng.uniform(50, 66) if w else rng.uniform(72, 95)
        elif k == "rise":
            t0, dt = (rng.uniform(28, 45), rng.uniform(0.25, 0.55)) if w else (rng.uniform(35, 60), rng.uniform(0.9, 1.6))
        elif k == "vib":
            amp = rng.uniform(300, 650) if w else rng.uniform(950, 1900)
        elif k == "dist":
            d0, spd = (rng.uniform(55, 115) if w else rng.uniform(5, 40)), 0.0
        else:
            d0, spd = (rng.uniform(130, 200), rng.uniform(4, 8)) if w else (rng.uniform(150, 200), rng.uniform(12, 18))
    ph = rng.uniform(0, 2 * math.pi)
    t = [round(min(99.0, t0 + dt * i + rng.gauss(0, 0.08)) * 16) for i in range(N_WIN)]
    v = [min(4095, max(0, round(2048 + amp * math.sin(ph + 2 * math.pi * 0.37 * i) + rng.gauss(0, 12)))) for i in range(N_WIN)]
    d = [min(D_MAX, max(D_MIN, round(d0 - spd * i + rng.gauss(0, 0.7)))) for i in range(N_WIN)]
    return {"age": [rng.randint(0, 150) for _ in range(3)], "t": t, "v": v, "d": d, "label": label}


def dataset(n, seed):
    rng = random.Random(seed)
    return [gen_window(rng, i % N_CLS) for i in range(n)]


TRAIN = (3000, 2901)
TEST = (1500, 2902)


# ---------------------------------------------------------------- 모델
def load_float():
    return json.loads(MODEL_JSON.read_text())


def load_qmodel():
    qm = quantize_model(load_float(), 8)
    w = [row + [0] * (N_IN - N_FEAT) for row in qm["w"]] + [[0] * N_IN for _ in range(N_CLASS - N_CLS)]
    b = list(qm["b"]) + [UNUSED_BIAS] * (N_CLASS - N_CLS)
    return dict(qm, w=w, b=b)


def model_id(qm):
    w = bytes(v & 0xFF for row in qm["w"] for v in row)
    return zlib.crc32(w + b"".join(struct.pack("<q", v) for v in qm["b"])) & 0xFFFFFFFF


def golden(f, qm):
    _, scores, cls, ovf = model(f + [0] * (N_IN - N_FEAT), qm["w"], qm["b"], 41, 40, 8)
    assert not ovf and 0 <= cls < N_CLS
    return scores[:N_CLS], cls


def float_class(f, fm):
    z = [sum(w * x / 127 for w, x in zip(row, f)) + b for row, b in zip(fm["weight"], fm["bias"])]
    return max(range(N_CLS), key=lambda c: (z[c], -c))


# ---------------------------------------------------------------- 경보 정책
class Policy:
    def __init__(self):
        self.reset()

    def reset(self):
        self.state, self.latch, self.cnt, self.hold = UNKNOWN, 0, 0, 0

    def cand(self, c):
        if SEV[c] >= SEV[self.state]:
            self.state, self.cnt = c, 0
            if c == FAULT:
                self.latch = 1
        elif self.latch:
            self.cnt = 0
        else:
            self.hold = SEV[c] if self.cnt == 0 else max(self.hold, SEV[c])
            if self.cnt == CLEAR_N - 1:
                self.state, self.cnt = CODE_OF_SEV[self.hold], 0
            else:
                self.cnt += 1

    def ack(self):
        if self.latch:
            self.latch, self.cnt = 0, 0
            return 1
        return 0

    def step(self, rst, cv, c, ack):
        """RTL 한 클록(p3_alarm_policy): 반환 ack_ok."""
        if rst:
            self.reset()
            return 0
        if cv:
            self.cand(c)
            return 0
        return self.ack() if ack else 0


# ---------------------------------------------------------------- 표시·프레임
def disp(state, latch, low_byte, digit2, error_code=None):
    """FND: [3] 상태 코드(점 = latch), [2] 이유 비트, [1:0] seq 하위 바이트 또는 'E'+오류 코드."""
    on = 0b1011 if digit2 is None else 0b1111
    lo = (0xE << 4 | error_code) if error_code is not None else (low_byte & 0xFF)
    word = (state << 12) | ((digit2 or 0) << 8) | lo | (on << FND_ON_SHIFT) | (latch << (FND_DP_SHIFT + 3))
    led = (1 << state) | (LED_ALARM if state != NORMAL else 0) | (LED_LATCH if latch else 0)
    return word, led | (LED_ERROR if error_code is not None else 0)


def frame(cmd, payload=b""):
    body = cmd + payload
    return SYNC + body + struct.pack(">H", crc16(body))


def sensor_payload(seq, mid, s):
    p = struct.pack("<HI3H", seq, mid, *s["age"])
    for t, v, d in zip(s["t"], s["v"], s["d"]):
        p += struct.pack("<hHH", t, v, d)
    return p


def sensor_frame(seq, mid, s):
    return frame(CMD_SENSOR, sensor_payload(seq, mid, s))


class Firmware:
    """펌웨어 응답 기대값(호스트 판정용). 각 메서드는 기대 dict(주 줄 필드 + fnd/led)를 돌려준다."""

    def __init__(self, qm):
        self.qm, self.mid, self.pol, self.bad = qm, model_id(qm), Policy(), 0

    def _state(self, src, cand, umask, fmask, seq, extra=None):
        self.pol.cand(cand)
        fnd, led = disp(self.pol.state, self.pol.latch, seq if seq >= 0 else 0, fmask | umask)
        e = dict(kind="STATE", src=src, seq=seq, cand=cand, state=self.pol.state, latch=self.pol.latch,
                 fmask=fmask, umask=umask, fnd=fnd, led=led)
        e.update(extra or {})
        return e

    def sensor(self, seq, mid, s):
        if mid != self.mid:
            return self.proto_error("MODEL", seq)
        self.bad = 0
        fm, um = guard(s)
        if fm or um:
            return self._state("FRAME", FAULT if fm else UNKNOWN, um, fm, seq, dict(guard="FAULT" if fm else "UNKNOWN"))
        f = features(s)
        sc, cls = golden(f, self.qm)
        return self._state("FRAME", cls, 0, 0, seq, dict(guard="OK", feat=f, scores=sc, npu=cls))

    def proto_error(self, name, seq=-1):
        self.bad += 1
        e = dict(kind="ERROR", code=ERR[name], seq=seq)
        if self.bad >= LINK_BAD_N:
            e.update(state_line=self._state("LINK_BAD", UNKNOWN, B_LINK, 0, -1))
        fnd, led = disp(self.pol.state, self.pol.latch, 0, None, ERR[name])
        e.update(fnd=fnd, led=led)
        return e

    def link_timeout(self):
        return self._state("LINK_TIMEOUT", UNKNOWN, B_LINK, 0, -1)

    def ack(self):
        ok = self.pol.ack()
        fnd, led = disp(self.pol.state, self.pol.latch, 0, None)
        return dict(kind="ACK", ok=ok, state=self.pol.state, latch=self.pol.latch, fnd=fnd, led=led)

    def boot(self):
        fnd, led = disp(self.pol.state, self.pol.latch, 0, None)
        return dict(kind="BOOT", fnd=fnd, led=led)


# ---------------------------------------------------------------- 출력물
def write_header(out):
    qm = load_qmodel()
    mid = model_id(qm)
    lines = ["/* 자동 생성: part03/ch29/reference/sensor_reference.py (센서 6특징 → 3상태, 5-1 IP 10×784 형태) */",
             "#ifndef SENSOR_MODEL_H", "#define SENSOR_MODEL_H", "#include <stdint.h>",
             f"#define SENSOR_MODEL_ID 0x{mid:08x}u",
             "static const int8_t model_w[10][784] = {"]
    lines += ["  {" + ",".join(map(str, row[:N_FEAT])) + "}," for row in qm["w"]]     # 나머지는 C 규칙상 0
    lines += ["};", "static const int64_t model_b[10] = {" + ",".join(f"{v}LL" for v in qm["b"]) + "};", "#endif", ""]
    out.write_text("\n".join(lines))
    print(f"SENSOR_HEADER_DONE model_id={mid:08x} w={qm['w'][0][:N_FEAT]}...")


def evaluate():
    fm, qm = load_float(), load_qmodel()
    for name, (n, seed) in (("train", TRAIN), ("test", TEST)):
        ds = dataset(n, seed)
        assert all(guard(s) == (0, 0) for s in ds)
        fc = sum(float_class(features(s), fm) == s["label"] for s in ds)
        ic = sum(golden(features(s), qm)[1] == s["label"] for s in ds)
        agree = sum(float_class(features(s), fm) == golden(features(s), qm)[1] for s in ds)
        conf = [[0] * N_CLS for _ in range(N_CLS)]
        for s in ds:
            conf[s["label"]][golden(features(s), qm)[1]] += 1
        print(f"EVAL {name} n={n} float_acc={100 * fc / n:.2f}% int8_acc={100 * ic / n:.2f}% "
              f"float_int8_agree={agree}/{n} int8_confusion(label→pred)={conf}")


def policy_vectors(out, n_rand=4000, seed=2903):
    """RTL 정책 벡터: rst cv cand ack | 기대 state latch cnt ack_ok alarm."""
    rng = random.Random(seed)
    ev = [(1, 0, 0, 0)] * 2
    N, W, F, U = NORMAL, WARNING, FAULT, UNKNOWN
    directed = [N, N, N, W, N, N, N, F, N, N, N, "A", N, N, W, N, N, U, N, W, N, "A", F, "A", F, N, N, "A", N, N, N]
    for x in directed:
        ev.append((0, 0, 0, 1) if x == "A" else (0, 1, x, 0))
        ev.append((0, 0, 0, 0))
    ev += [(0, 1, F, 1), (0, 1, N, 1), (0, 1, N, 0), (0, 0, 0, 1), (1, 0, 0, 0), (0, 1, N, 0)]
    for _ in range(n_rand):
        r = rng.random()
        ev.append((1 if r < 0.01 else 0, int(rng.random() < 0.6), rng.choice([N, N, N, W, W, F, U]), int(rng.random() < 0.15)))
    p = Policy()
    lines = []
    for rst, cv, c, a in ev:
        ok = p.step(rst, cv, c, a)
        lines.append(f"{rst} {cv} {c} {a} {p.state} {p.latch} {p.cnt} {ok} {int(p.state != NORMAL)}")
    out.write_text("\n".join(lines) + "\n")
    print(f"POLICY_VECTORS n={len(lines)} directed={len(directed)}")


def selftest():
    assert crc16(b"123456789") == 0x29B1
    qm = load_qmodel()
    s = dataset(3, TEST[1])[0]
    f = sensor_frame(0x0102, model_id(qm), s)
    assert len(f) == 2 + 1 + PAYLOAD_BYTES + 2 and crc16(f[2:]) == 0
    assert golden([0] * N_FEAT, qm)[0] == qm["b"][:N_CLS]
    # 가이드 예제와 같은 순서: 결측 → UNKNOWN, 범위 밖 → FAULT, 정상 → 모델 입력
    ok = {"age": [0, 0, 0], "t": [23 * 16] * 8, "v": [2048 + (60 if i % 2 else -60) for i in range(8)], "d": [60] * 8}
    assert guard(ok) == (0, 0)
    assert guard(dict(ok, t=[T_MISS] + ok["t"][1:])) == (0, B_T)
    assert guard(dict(ok, t=[150 * 16] * 8)) == (B_T, 0)
    assert guard(dict(ok, v=[4095] * 8)) == (B_V, 0) and guard(dict(ok, v=[3] * 8)) == (B_V, 0)
    assert guard(dict(ok, d=[1] * 8)) == (B_D, 0) and guard(dict(ok, age=[0, 0, 501])) == (0, B_D)
    assert guard(dict(ok, t=[T_MISS] * 8, d=[500] * 8)) == (B_D, B_T)           # FAULT 비트가 있으면 후보 FAULT
    assert features(ok) == [0, 0, 0, 0, q(65, 160), 0]
    hot = dict(ok, t=[70 * 16 + i for i in range(8)], v=[2048 + (1000 if i % 2 else -1000) for i in range(8)],
               d=[200 - 20 * i for i in range(8)])
    assert features(hot) == [64, 0, 92, 127, 51, 127]                    # (1127-720)·127//800 = 64 …
    p = Policy()
    trace = []
    for c in [NORMAL, NORMAL, NORMAL, WARNING, NORMAL, NORMAL, NORMAL, FAULT, NORMAL, NORMAL, NORMAL]:
        p.cand(c)
        trace.append(p.state)
    U, N, W, F = UNKNOWN, NORMAL, WARNING, FAULT
    assert trace == [U, U, N, W, W, W, N, F, F, F, F]                   # 부팅 UNKNOWN, 3회 연속 뒤 하향, FAULT 래치
    assert p.ack() == 1 and p.ack() == 0
    for c in [NORMAL, WARNING, NORMAL]:
        p.cand(c)
    assert p.state == WARNING                                             # 3개 중 가장 심각한 상태로 내림
    assert disp(FAULT, 1, 0x1A7, 1) == (0x2_1A7 | (0xF << 16) | (1 << 23), (1 << 2) | LED_ALARM | LED_LATCH)
    print(f"SENSOR_REFERENCE_SELFTEST_PASS model_id={model_id(qm):08x} frame_bytes={len(f)}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--selftest", action="store_true")
    p.add_argument("--eval", action="store_true")
    p.add_argument("--header", type=Path)
    p.add_argument("--policy-vectors", type=Path)
    a = p.parse_args()
    if a.selftest:
        selftest()
    if a.eval:
        evaluate()
    if a.header:
        write_header(a.header)
    if a.policy_vectors:
        policy_vectors(a.policy_vectors)


if __name__ == "__main__":
    main()
