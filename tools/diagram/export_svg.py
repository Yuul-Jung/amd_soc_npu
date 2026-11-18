#!/usr/bin/env python3
"""svg-flow-editor(Yuul-Jung/svg-flow-editor)로 도면 JSON을 SVG로 내보낸다.

  python3 tools/diagram/export_svg.py                         # 편집기: GitHub Pages
  python3 tools/diagram/export_svg.py --editor ../svg-flow-editor/index.html   # 로컬 사본
  python3 tools/diagram/export_svg.py ch10/diagrams/ch10_npu_core_fsm.json      # 특정 파일만

동작: 편집기를 브라우저(Playwright Chromium)로 열고 '작업 불러오기'에 JSON을 넣은 뒤
편집기 내장 '도면 품질 검사'(inspectDiagramQuality)를 실행한다. 0건일 때만
편집기의 svgString() 결과를 같은 이름의 .svg로 저장한다. 1건 이상이면 저장하지 않고 exit 1.
JSON이 원본이며 SVG는 산출물이다. 사람이 편집기에서 고친 JSON을 넣고 다시 실행하면 된다.

내보내기 보정 (편집기 저장소는 수정하지 않음):
  1. 제목 클릭 영역(rect.heading-hit)은 편집기 CSS로만 투명하므로 SVG에서 제거한다.
  2. 간선 라벨: 편집기 기본 위치(첫 구간 x+45 가운데 정렬)는 긴 조건문이 선에 걸친다.
     각 구간의 위·아래·좌·우 후보 중 도형·다른 선·다른 라벨·캔버스 밖과 겹치지 않는
     첫 위치로 옮긴다. 자리가 없으면 저장하지 않고 실패로 보고한다.
"""

PLACE_LABELS = r"""() => {
  const svg = document.getElementById('canvas');
  svg.querySelectorAll('.heading-hit').forEach(el => el.remove());
  const W = scene.width, H = scene.height, top = 130;
  const rects = scene.nodes.map(n => ({l: n.x - n.w/2 - 4, r: n.x + n.w/2 + 4, t: n.y - n.h/2 - 4, b: n.y + n.h/2 + 4}));
  const segs = [];
  scene.edges.forEach(e => { const p = edgePath(e) || []; for (let i = 1; i < p.length; i++) segs.push({e: e.id, a: p[i-1], b: p[i]}); });
  const hit = (bb, s) => { const l = Math.min(s.a[0], s.b[0]) - 3, r = Math.max(s.a[0], s.b[0]) + 3, t = Math.min(s.a[1], s.b[1]) - 3, b = Math.max(s.a[1], s.b[1]) + 3;
                           return bb.x < r && bb.x + bb.width > l && bb.y < b && bb.y + bb.height > t; };
  const over = (bb, q) => bb.x < q.r && bb.x + bb.width > q.l && bb.y < q.b && bb.y + bb.height > q.t;
  const placed = [], fails = [];
  for (const e of scene.edges) {
    if (!e.label) continue;
    const t = svg.querySelector(`[data-edge="${e.id}"] text.edge-label`); if (!t) continue;
    const p = edgePath(e) || [];
    const sharedStart = scene.edges.some(o => o !== e && o.from === e.from && o.fp === e.fp);
    let idx = [...Array(p.length - 1).keys()];
    if (sharedStart) idx = idx.reverse();
    const cands = [];
    for (const i of idx) {
      const a = p[i], b = p[i+1];
      if (a[0] === b[0]) { const y = (a[1] + b[1]) / 2 + 5; cands.push(['start', a[0] + 10, y], ['end', a[0] - 10, y]); }
      else { const x = (a[0] + b[0]) / 2; cands.push(['middle', x, a[1] - 9], ['middle', x, a[1] + 21]); }
    }
    let ok = false;
    for (const [anc, x, y] of cands) {
      t.setAttribute('text-anchor', anc); t.setAttribute('x', x); t.setAttribute('y', y);
      const bb = t.getBBox();
      if (bb.x < 4 || bb.x + bb.width > W - 4 || bb.y < top || bb.y + bb.height > H - 4) continue;
      if (rects.some(q => over(bb, q))) continue;
      if (segs.some(s => hit(bb, s))) continue;
      if (placed.some(q => over(bb, q))) continue;
      placed.push({l: bb.x - 3, r: bb.x + bb.width + 3, t: bb.y - 2, b: bb.y + bb.height + 2}); ok = true; break;
    }
    if (!ok) fails.push('라벨 자리 없음: ' + e.id + ' (' + e.label + ')');
  }
  return fails;
}"""
import glob, hashlib, os, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PAGES = "https://yuul-jung.github.io/svg-flow-editor/"


def main():
    args = sys.argv[1:]
    editor = PAGES
    if "--editor" in args:
        i = args.index("--editor")
        editor = "file://" + os.path.abspath(args[i + 1])
        del args[i:i + 2]
    files = args or sorted(glob.glob(os.path.join(ROOT, "diagrams", "*.json")) + glob.glob(os.path.join(ROOT, "ch[0-9][0-9]", "diagrams", "*.json")))
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("DIAGRAM_EXPORT_NOT_RUN: playwright 미설치 (pip install playwright && python3 -m playwright install chromium)")
        return 2
    fails = 0
    with sync_playwright() as pw:
        b = pw.chromium.launch()
        pg = b.new_page(viewport={"width": 1600, "height": 1000})
        pg.on("dialog", lambda d: d.accept())
        for f in files:
            f = os.path.abspath(f)
            rel = os.path.relpath(f, ROOT)
            pg.goto(editor)
            pg.wait_for_function("typeof svgString==='function' && typeof inspectDiagramQuality==='function'")
            pg.set_input_files("#loadJSON", f)
            pg.wait_for_function("document.getElementById('fileStatus').textContent.includes('불러오기 완료')", timeout=10000)
            findings = pg.evaluate("inspectDiagramQuality().map(x=>x.message)")
            if findings:
                fails += 1
                print(f"DIAGRAM_QUALITY_FAIL {rel}")
                for m in findings:
                    print("  -", m)
                continue
            label_fail = pg.evaluate(PLACE_LABELS)
            if label_fail:
                fails += 1
                print(f"DIAGRAM_LABEL_FAIL {rel}")
                for m in label_fail:
                    print("  -", m)
                continue
            svg = pg.evaluate("svgString()")
            if svg.startswith("<?xml"):
                svg = svg.split("?>", 1)[1].lstrip()
            src = editor if editor.startswith("http") else "svg-flow-editor (로컬 사본)"
            digest = hashlib.sha256(open(f, "rb").read()).hexdigest()
            svg = svg.replace(">", f"><!-- 원본: {rel} · json-sha256: {digest} · 생성: {src} · 직접 수정 금지 -->", 1)
            out = f[:-5] + ".svg"
            with open(out, "w", encoding="utf-8") as fh:
                fh.write(svg.rstrip() + "\n")
            print(f"DIAGRAM_EXPORT_PASS {rel} → {os.path.relpath(out, ROOT)} (품질 검사 0건 · 라벨 배치 보정)")
        b.close()
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
