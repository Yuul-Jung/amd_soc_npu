#!/usr/bin/env python3
"""5장 SoC 구조도 원본(svg-flow-editor JSON)을 VS Code 판 21장 빌드 요약에서 만든다.

  python3 p05/diagrams/make_soc_map.py
  python3 tools/diagram/export_svg.py --editor <svg-flow-editor>/index.html p05/diagrams/soc_map.json

주소·인터럽트는 part03/ch21/validation/soc_summary.md (Vivado Address Editor 실제 값) 표에서만 읽는다.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "part03" / "ch21" / "validation" / "soc_summary.md"
OUT = Path(__file__).with_name("soc_map.json")

PRESET = {"navy": ("#1F3A5F", "#172439", "#273e5e"), "accent": ("#4635B1", "#2a1f78", "#3b2d99"),
          "gray": ("#6b6b6b", "#333333", "#555555")}


def table_after(text, title_prefix):
    """제목 줄 뒤 첫 마크다운 표의 행들 (머리·구분 줄 제외)."""
    i = text.index(title_prefix)
    rows = []
    for ln in text[i:].splitlines()[1:]:
        if ln.startswith("|"):
            cells = [c.strip() for c in ln.strip().strip("|").split("|")]
            if set(cells[0]) <= set("-: "):
                continue
            rows.append(cells)
        elif rows:
            break
    return rows[1:]


ROLE = {"axi_gpio_0": "GPIO LED·SW", "axi_gpio_btn": "GPIO 버튼", "axi_uartlite_0": "UART Lite 115200",
        "axi_timer_0": "Timer", "axi_intc_0": "INTC", "ip06_seg7": "7세그먼트 (ip_seg7)", "p3_npu_0": "NPU (구 20장 IP)"}


def node(i, x, y, w, title, sub, preset="navy", h=72):
    stroke, text, subc = PRESET[preset]
    return {"id": i, "type": "rect", "x": x, "y": y, "w": w, "h": h, "title": title, "sub": sub, "fill": "none",
            "autoFit": True, "pad": 6, "padY": 4, "fontMain": 20, "fontSub": 15, "textAlign": "center",
            "strokeColor": stroke, "strokeWidth": 3.0 if preset != "accent" else 3.6, "textColor": text,
            "subTextColor": subc, "preset": preset}


def edge(a, b, fp, tp, label="", color="#1F3A5F"):
    return {"id": f"{a}-{b}", "from": a, "to": b, "fp": fp, "tp": tp, "label": label, "route": "auto",
            "strokeColor": color, "strokeWidth": 2.6, "arrowSize": 13, "labelFont": 15}


def main():
    text = SRC.read_text(encoding="utf-8")
    amap = table_after(text, "## 주소 맵")
    irq = table_after(text, "## 인터럽트")
    plain = lambda s: re.sub(r"[*`]", "", s)
    periph = []
    for idx, seg, base, size, note in amap:
        if base in ("—", "-") or "LMB" in seg:
            continue
        name = plain(seg).split(" ", 1)
        periph.append((plain(idx), name[0], name[1] if len(name) > 1 else "", plain(base), plain(size)))
    irq_of = {}
    for inp, conn in irq:
        m = re.search(r"([a-z0-9_]+)/", plain(conn))
        if m:
            irq_of[m.group(1)] = plain(inp)

    W, x_cpu, x_bus, x_dev = 1280, 190, 520, 960
    mid = 150 + 92 * (len(periph) - 1) // 2
    nodes = [node("cpu", x_cpu, mid, 300, "MicroBlaze V (RV32)", "100 MHz · 인터럽트 ← axi_intc_0"),
             node("lmb", x_cpu, mid + 170, 300, "LMB BRAM", "0x0000_0000 · 64 KB · 프로그램·데이터"),
             node("smc", x_bus, mid, 220, "AXI SmartConnect", f"axi_smc · 마스터 1 → {len(periph)}", h=96)]
    edges = [edge("cpu", "smc", "right", "left", "M_AXI_DP"), edge("cpu", "lmb", "bottom", "top", "LMB")]
    intc = None
    for k, (idx, seg, desc, base, size) in enumerate(periph):
        nid = f"d{k}"
        is_npu = "npu" in seg
        role = ROLE.get(seg, seg)
        sub = f"{seg} · {base}" + (f" · {irq_of[seg]}" if seg in irq_of else "")
        if "intc" in seg:
            short = {"axi_timer_0": "Timer", "axi_uartlite_0": "UART", "axi_gpio_btn": "BTN", "p3_npu_0": "NPU"}
            sub = f"{seg} · {base} · " + ", ".join(f"{v} {short.get(k, k)}" for k, v in sorted(irq_of.items(), key=lambda kv: int(kv[1][2:])))
        title = (f"{idx} " if idx not in ("—", "-") else "") + role
        nodes.append(node(nid, x_dev, 0, 540, title, sub, "accent" if is_npu else "navy"))
        nodes[-1]["autoFit"] = False
        nodes[-1]["y"] = 150 + 92 * k
        edges.append(edge("smc", nid, "right", "left"))
        if "intc" in seg:
            intc = nid
    doc = {
        "version": 3, "chapter": "P05", "verification": "VS Code 판 21장 Vivado Address Editor 값 (soc_summary.md)",
        "pageTitle": "5장 SoC 구조 · 동결 주소맵 (안 A)", "title": "5장 SoC 구조 · 동결 주소맵 (안 A)",
        "subtitle": "MicroBlaze V가 AXI로 주변 장치 7개를 읽고 쓴다. NPU(구 20장 IP)는 0x44A0_0000, 인터럽트 In12",
        "width": W, "height": 150 + 92 * (len(periph) - 1) + 80,
        "headings": {"title": {"x": 640.0, "y": 48, "w": 1200, "h": 56, "size": 28, "align": "left", "autoFit": True},
                     "subtitle": {"x": 640.0, "y": 96, "w": 1200, "h": 34, "size": 16, "align": "left", "autoFit": True}},
        "settings": {"fontMain": 20, "fontSub": 15, "stroke": 3.0, "gap": 40, "pad": 6, "padY": 4, "defaultPreset": "navy"},
        "sourceFile": str(SRC.relative_to(ROOT)), "role": "SoC 구조도",
        "nodes": nodes, "edges": edges,
    }
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"P05_SOC_MAP_JSON nodes={len(nodes)} edges={len(edges)} periph={len(periph)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
