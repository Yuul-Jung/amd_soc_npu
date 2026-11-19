#!/usr/bin/env python3
"""6장 응용 지도 원본(svg-flow-editor JSON). 어느 응용이 21장 비트스트림에 ELF만 바꿔 올라가는지 한눈에.

  python3 p06/diagrams/make_app_map.py
  python3 tools/diagram/export_svg.py --editor <svg-flow-editor>/index.html p06/diagrams/app_map.json

응용 목록·서브젝트 번호는 p06/project.json에서 읽는다 (board 값: elf · own · none).
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).with_name("app_map.json")
PRESET = {"navy": ("#1F3A5F", "#172439", "#273e5e"), "accent": ("#4635B1", "#2a1f78", "#3b2d99"),
          "gray": ("#6b6b6b", "#333333", "#555555")}


def node(i, x, y, w, title, sub, preset="navy", h=72):
    stroke, text, subc = PRESET[preset]
    return {"id": i, "type": "rect", "x": x, "y": y, "w": w, "h": h, "title": title, "sub": sub, "fill": "none",
            "autoFit": False, "pad": 6, "padY": 4, "fontMain": 20, "fontSub": 15, "textAlign": "center",
            "strokeColor": stroke, "strokeWidth": 3.0 if preset != "accent" else 3.6, "textColor": text,
            "subTextColor": subc, "preset": preset}


def edge(a, b, fp, tp, label="", color="#1F3A5F"):
    return {"id": f"{a}-{b}", "from": a, "to": b, "fp": fp, "tp": tp, "label": label, "route": "auto",
            "strokeColor": color, "strokeWidth": 2.6, "arrowSize": 13, "labelFont": 15}


def main():
    p = json.loads((ROOT / "p06" / "project.json").read_text(encoding="utf-8"))
    subs = p["subjects"]
    y0, dy = 160, 100
    mid = y0 + dy * (len(subs) - 1) // 2
    nodes = [node("pc", 140, mid, 240, "PC 호스트 (Python)", "그림·센서 창·모델 프레임"),
             node("soc", 560, mid, 320, "21장 비트스트림 (5장)", "MicroBlaze V + NPU · 동결 주소맵 안 A", h=96)]
    edges = [edge("pc", "soc", "right", "left", "UART 115200")]
    for k, s in enumerate(subs):
        kind = s["app"]
        preset = "accent" if s.get("common") else ("gray" if kind != "elf" else "navy")
        tag = {"elf": "ELF만 교체", "own": "별도 비트스트림 ⚠ 재빌드 대기", "none": "RTL만 · 보드 없음"}[kind]
        nid = f"a{k}"
        nodes.append(node(nid, 950, y0 + dy * k, 380, f"{s['code']} {s['title']}", f"구 {int(s['ch'][2:]):02d}장 · {tag}", preset))
        if kind == "elf":
            edges.append(edge("soc", nid, "right", "left"))
        elif kind == "own":
            edges.append(edge("soc", nid, "right", "left", "", "#6b6b6b"))
    doc = {
        "version": 3, "chapter": "P06", "verification": "p06/project.json 서브젝트 목록",
        "pageTitle": "6장 응용 지도", "title": "6장 응용 지도 · 5장 SoC 위에 올리는 응용",
        "subtitle": "보라 = 공통 서브젝트, 남색 = ELF만 교체, 회색 = 별도 비트스트림 또는 보드 없음",
        "width": 1170, "height": y0 + dy * (len(subs) - 1) + 80,
        "headings": {"title": {"x": 585.0, "y": 48, "w": 1100, "h": 56, "size": 28, "align": "left", "autoFit": True},
                     "subtitle": {"x": 585.0, "y": 96, "w": 1100, "h": 34, "size": 16, "align": "left", "autoFit": True}},
        "settings": {"fontMain": 20, "fontSub": 15, "stroke": 3.0, "gap": 40, "pad": 6, "padY": 4, "defaultPreset": "navy"},
        "sourceFile": "p06/project.json", "role": "응용 지도", "nodes": nodes, "edges": edges,
    }
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"P06_APP_MAP_JSON nodes={len(nodes)} edges={len(edges)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
