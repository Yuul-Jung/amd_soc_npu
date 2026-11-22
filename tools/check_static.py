#!/usr/bin/env python3
"""amd_soc_npu 정적 검사 — HTML 링크·SHA·RTL 계층 구조. RTL 시뮬레이션이 아님.
amd_soc_rtl/part03/validation/check_static.py 에서 경로를 amd_soc_npu 구조에 맞게 조정."""
from __future__ import annotations
import hashlib
import json
import re
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]   # /…/amd_soc_npu
issues: list[str] = []
verified = 0


def check(condition: bool, message: str):
    global verified
    verified += 1
    if not condition:
        issues.append(message)


# ── course.json 기본 검사 ────────────────────────────────────────────────────
course = json.loads((ROOT / "course.json").read_text(encoding="utf-8"))
chapters = course["chapters"]
check(len(chapters) == 32, "00~31장: 32개 항목이 필요합니다.")
check([x["number"] for x in chapters] == list(range(32)),
      "장 번호가 00~31 연속이어야 합니다.")
check([x["id"] for x in chapters] == [f"ch{i:02d}" for i in range(32)],
      "차시 ID가 ch00~ch31 연속이어야 합니다.")

# ── 존재하는 HTML 파일만 검사 (TODO인 장은 경고 없이 건너뜀) ─────────────────
for chapter in chapters:
    page = ROOT / chapter["file"]
    if not page.is_file():
        continue   # TODO 장은 CI 초기에 허용
    body = page.read_text(encoding="utf-8")
    check(f'data-chapter="{chapter["id"]}"' in body,
          "HTML data-chapter wrong: " + chapter["file"])
    check(body.count('<section class="section"') >= 5,
          "실습 섹션이 부족함: " + chapter["file"])
    check("assets/education/site.css" in body,
          "중앙 CSS 누락 " + chapter["file"])
    check("assets/education/site.js" in body,
          "좌측 탐색 JS 누락 " + chapter["file"])

# ── index.html 에서 모든 장 링크 확인 (존재하는 파일만) ─────────────────────
index_html_path = ROOT / "index.html"
if index_html_path.is_file():
    index_html = index_html_path.read_text(encoding="utf-8")
    for chapter in chapters:
        if (ROOT / chapter["file"]).is_file():
            check(chapter["file"] in index_html,
                  "INDEX navigation missing: " + chapter["file"])

# ── 상대 링크 및 앵커 검사 ──────────────────────────────────────────────────
class LocalLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls: list[str] = []
        self.ids: set[str] = set()

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name == "id" and value:
                self.ids.add(value)
            if name in ("href", "src") and value:
                self.urls.append(value)


link_checks = 0
# 제1부·제2부(partNN) 안내서·INDEX도 같은 방식으로 링크 검사 (목록: partNN/course.json)
part01_pages = []
for part in ("part01", "part02"):
    pc = json.loads((ROOT / part / "course.json").read_text(encoding="utf-8"))
    part01_pages += [ROOT / part / "index.html"] + [ROOT / part / ch["file"] for ch in pc["chapters"]]
for page in part01_pages:
    check(page.is_file(), "부 안내서 누락: " + str(page.relative_to(ROOT)))
all_pages = ([ROOT / "index.html"]
             + [ROOT / ch["file"] for ch in chapters]
             + part01_pages)
for page in all_pages:
    if not page.is_file():
        continue
    body = page.read_text(encoding="utf-8")
    parser = LocalLinks()
    parser.feed(body)
    for raw in parser.urls:
        if raw.startswith("//"):
            continue
        url = urlsplit(raw)
        if url.scheme:
            continue
        if not url.path:
            if url.fragment:
                link_checks += 1
                check(unquote(url.fragment) in parser.ids,
                      f"Broken anchor: {page.name} -> {raw}")
            continue
        link_checks += 1
        target = (page.parent / unquote(url.path)).resolve()
        check(target.is_relative_to(ROOT) and target.is_file(),
              f"Broken link: {page.name} -> {raw}")

# ── ch01~ch10 SHA 검증 (amd_soc_rtl 에서 복사한 로그 대상) ─────────────────
for n in range(1, 11):
    manifest = ROOT / f"ch{n:02d}/validation/source_sha256.txt"
    if not manifest.is_file():
        # 아직 이전하지 않은 경우 경고만 등록
        issues.append(f"ch{n:02d}: source_sha256.txt 없음 (마이그레이션 미완)")
        continue
    for line in manifest.read_text().splitlines():
        entry = line.split(maxsplit=1)
        if len(entry) != 2:
            issues.append(f"Invalid manifest line in ch{n:02d}/validation/source_sha256.txt")
            continue
        expected, filename = entry
        # amd_soc_rtl 경로 → amd_soc_npu 경로로 변환
        rel = filename.strip().lstrip("*")
        rel = rel.replace("part03/", "")
        filepath = ROOT / rel
        check(filepath.is_file(), f"source missing {rel}")
        if filepath.is_file():
            got = hashlib.sha256(filepath.read_bytes()).hexdigest()
            check(got == expected, f"SOURCE_SHA256_MISMATCH {rel}")

# ── 통합 NPU 계층 검사 ──────────────────────────────────────────────────────
critical_files = [
    "common/rtl/uart_rx.v",
    "common/rtl/uart_tx.v",
    "common/rtl/uart_core.v",
    "common/rtl/uart_echo_controller.v",
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
for path in critical_files:
    check((ROOT / path).is_file(), "Missing integration file: " + path)

engine_path = ROOT / "mini_npu/rtl/npu_engine4.v"
lane_path   = ROOT / "mini_npu/rtl/npu_dsp_mac_lane.v"
top_path    = ROOT / "mini_npu/rtl/basys3_npu_top.v"

if engine_path.is_file():
    engine = engine_path.read_text()
    check("npu_dsp_mac_lane lane0" in engine and
          "npu_dsp_mac_lane lane3" in engine,
          "4-lane DSP accumulation not instantiated in npu_engine4")

if lane_path.is_file():
    lane = lane_path.read_text()
    check("dsp_multiplier" in lane, "dsp_multiplier not referenced in npu_dsp_mac_lane")

if top_path.is_file():
    top = top_path.read_text()
    check("always" not in top and "assign" not in top,
          "basys3_npu_top contains functional logic (should be structural)")

# ── XDC 검사 ────────────────────────────────────────────────────────────────
xdc_path = ROOT / "mini_npu/constraints/basys3_npu.xdc"
if xdc_path.is_file():
    xdc = xdc_path.read_text()
    pins = re.findall(r"PACKAGE_PIN\s+([A-Z][0-9]+)", xdc)
    check(len(pins) == len(set(pins)), "XDC에 중복 핀 할당이 있습니다")
    for port in ["clk", "btnC", "uart_rxd", "uart_txd"]:
        check(f"get_ports {port}" in xdc, f"XDC 필수 포트 누락: {port}")
    check("create_clock" in xdc and "-period 10.000" in xdc,
          "100 MHz 클록 제약 누락")

# ── 보안 검사 ───────────────────────────────────────────────────────────────
for secret_prefix in ("AKIA", "ghp_", "BEGIN PRIVATE KEY", "sk-proj-"):
    for path in critical_files[:5]:
        f = ROOT / path
        if f.is_file():
            check(secret_prefix not in f.read_text(),
                  f"Possible secret in {path}: {secret_prefix}")

# ── 결과 출력 ───────────────────────────────────────────────────────────────
out_dir = ROOT / "docs"
out_dir.mkdir(parents=True, exist_ok=True)
(out_dir / "static_audit.json").write_text(json.dumps({
    "kind": "STATIC_AUDIT_ONLY",
    "checks": verified,
    "link_checks": link_checks,
    "errors": issues,
    "rtl_simulation": "NOT_EXECUTED_BY_THIS_SCRIPT",
    "synthesis": "NOT_RUN",
    "board": "NOT_RUN"
}, ensure_ascii=False, indent=2) + "\n")

if issues:
    for msg in issues:
        print("STATIC_FAIL", msg)
    raise SystemExit(1)

print(f"STATIC_AUDIT_PASS checks={verified} links={link_checks} "
      f"chapters={len(chapters)} scope=files,hashes,links,hierarchy,XDC")
