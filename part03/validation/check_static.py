#!/usr/bin/env python3
"""제3부 코드·교재 파일 정합성 정적 검사. RTL 시뮬레이션이 아님."""
from __future__ import annotations
import hashlib
import json
import re
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
P3 = ROOT / "part03"
issues = []
verified = 0


def check(condition: bool, message: str):
    global verified
    verified += 1
    if not condition:
        issues.append(message)


course = json.loads((P3 / "course.json").read_text(encoding="utf-8"))
chapters = course["chapters"]
check(len(chapters) == 13, "00~12장: 13개 차시가 필요합니다.")
for chapter in chapters:
    page = P3 / chapter["file"]
    check(page.is_file(), "HTML missing " + str(page))
    if page.is_file():
        body = page.read_text(encoding="utf-8")
        check('data-chapter="' + chapter["id"] + '"' in body,
              "HTML data-chapter wrong: " + chapter["file"])
        check(body.count('<section class="section"') >= 5,
              "실습 섹션이 부족함: " + chapter["file"])
        check("../assets/education/site.css" in body,
              "중앙 CSS 누락 " + chapter["file"])
        check("../assets/education/site.js" in body,
              "좌측 탐색 JS 누락 " + chapter["file"])

check((P3 / "index.html").is_file(), "index.html missing")
for n in range(1, 11):
    chapter = P3 / f"ch{n:02d}"
    manifest = chapter / "validation/source_sha256.txt"
    check(manifest.is_file(), f"CH{n:02d}: 검증 원본 해시 누락")
    if not manifest.is_file():
        continue
    # 원본 기록에는 의존성 장의 이전 소스 SHA도 포함돼 있으므로 모두 확인한다.
    for line in manifest.read_text().splitlines():
        entry = line.split(maxsplit=1)
        if len(entry) != 2:
            issues.append(f"Invalid manifest line: {manifest.name}");continue
        expected, filename = entry
        filepath = ROOT / filename.strip().lstrip("*")
        check(filepath.is_file(), f"source missing {filename}")
        if filepath.is_file():
            got = hashlib.sha256(filepath.read_bytes()).hexdigest()
            check(got == expected, f"SOURCE_SHA256_MISMATCH {filename}")
    check((chapter / "scripts/run_sim.sh").is_file(),
          f"CH{n:02d} test script missing")

# 전체 UART→DSP/BRAM→NPU 경로의 필수 인스턴스 이름/모듈 선언 존재.
files = [
    "common/rtl/uart_rx.v", "common/rtl/uart_tx.v",
    "common/rtl/uart_core.v", "common/rtl/uart_echo_controller.v",
    "mini_npu/rtl/uart_npu_command_controller.v",
    "mini_npu/rtl/npu_dsp_mac_lane.v",
    "mini_npu/rtl/npu_engine4.v",
    "mini_npu/rtl/npu_reset_controller.v",
    "mini_npu/rtl/npu_display_controller.v",
    "mini_npu/rtl/basys3_npu_top.v",
    "mini_npu/tb/tb_npu_uart.sv",
    "mini_npu/tb/tb_npu_engine4.sv",
    "mini_npu/scripts/run_demo.sh",
    "mini_npu/scripts/run_engine.sh",
    "mini_npu/scripts/run_batch_00_12.sh",
]
for path in files:
    check((P3 / path).is_file(), "Missing integration file: " + path)
top = (P3 / "mini_npu/rtl/basys3_npu_top.v").read_text()
check("always" not in top and "assign" not in top and "function" not in top,
      "Top contains functional logic")
engine = (P3 / "mini_npu/rtl/npu_engine4.v").read_text()
lane = (P3 / "mini_npu/rtl/npu_dsp_mac_lane.v").read_text()
check("npu_dsp_mac_lane lane0" in engine and "npu_dsp_mac_lane lane3" in engine,
      "Four DSP accumulation lanes not instantiated")
check("dsp_multiplier" in lane, "Original DSP multiplier absent")

xdc = (P3 / "mini_npu/constraints/basys3_npu.xdc").read_text()
pins = re.findall(r"PACKAGE_PIN\s+([A-Z][0-9]+)", xdc)
check(len(pins) == len(set(pins)), "XDC duplicates physical pins")
for wire in ["clk", "btnC", "uart_rxd", "uart_txd"]:
    check(f"get_ports {wire}" in xdc, f"Missing XDC port {wire}")
check("create_clock" in xdc and "-period 10.000" in xdc,
      "100MHz clock constraint missing")

# 실행 대상 문자열과 실제 본문에 민감한 값을 직접 넣지 않는다.
for unsafe in ("AKIA", "ghp_", "BEGIN PRIVATE KEY", "sk-proj-"):
    check(unsafe not in engine and unsafe not in top,
          f"Possible secret detected: {unsafe}")

out = P3 / "validation/static_audit.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({
    "kind": "STATIC_AUDIT_ONLY",
    "checks": verified,
    "errors": issues,
    "rtl_simulation": "NOT_EXECUTED_BY_THIS_SCRIPT",
    "synthesis": "NOT_RUN",
    "board": "NOT_RUN"
}, ensure_ascii=False, indent=2) + "\n")
if issues:
    for message in issues:
        print("STATIC_FAIL", message)
    raise SystemExit(1)
print(f"STATIC_AUDIT_PASS checks={verified} chapters={len(chapters)} "
      "scope=files,hashes,links,hierarchy,XDC")
