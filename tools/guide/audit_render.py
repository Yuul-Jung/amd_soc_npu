#!/usr/bin/env python3
"""학습안내서 화면 점검 (rule_md STANDARD 7·10절, flowchart 11.2).

  pip install playwright && python3 -m playwright install chromium
  python3 tools/guide/audit_render.py                 # 로컬 파일
  python3 tools/guide/audit_render.py --base https://yuul-jung.github.io/amd_soc_npu/   # 배포본
  python3 tools/guide/audit_render.py --browser firefox   # chromium(기본)·firefox·webkit(Safari 엔진)
결과: docs/RENDER_AUDIT.md (통과/실패 판정과 근거). Playwright가 없으면 실행하지 않는다.
"""
import json, os, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
WIDTHS = [1920, 1366, 1024, 768, 390, 320]

JS_PAGE = r"""() => {
  const r = {};
  r.overflow = document.documentElement.scrollWidth - window.innerWidth;
  const hero = document.querySelector('.hero');
  r.hero_h = hero ? Math.round(hero.getBoundingClientRect().height) : null;
  const bg = hero ? getComputedStyle(hero, '::before').backgroundImage : '';
  r.hero_img = /hero-bookshelf\.jpg/.test(bg);
  r.paper = getComputedStyle(document.body).backgroundColor;
  r.nav_chapters = document.querySelectorAll('#course-nav a').length;
  r.links = [...document.querySelectorAll('#chapter-links a')].map(a => a.getAttribute('href'));
  r.codeblocks = document.querySelectorAll('.codeblock').length;
  r.copy_buttons = document.querySelectorAll('.codebar button').length;
  // SVG 글자끼리 겹침 검사 (같은 svg 안의 text 상자 교차).
  // 브라우저마다 글자 상자에 위아래 여백을 넣는 정도가 달라(Firefox가 큼) 바로 아랫줄과 몇 px 포개질 수 있으므로,
  // 세로로 작은 글자 높이의 35% 이상 포개질 때만 겹침으로 본다.
  r.svg_overlaps = [];
  r.svg_clipped = [];
  document.querySelectorAll('svg').forEach((svg, si) => {
    const t = [...svg.querySelectorAll('text')].map(e => [e.textContent, e.getBoundingClientRect()]);
    // 도면 밖으로 나가 잘리는 글자 (예: 긴 출력 포트 이름)
    const box = svg.getBoundingClientRect();
    t.forEach(([s, a]) => { if (a.width && (a.right > box.right + 1 || a.left < box.left - 1)) r.svg_clipped.push(`svg${si}: "${s}"`); });
    for (let i = 0; i < t.length; i++) for (let j = i + 1; j < t.length; j++) {
      const a = t[i][1], b = t[j][1];
      const ox = Math.min(a.right, b.right) - Math.max(a.left, b.left);
      const oy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
      if (ox > 1 && oy > 0.35 * Math.min(a.height, b.height)) r.svg_overlaps.push(`svg${si}: "${t[i][0]}" ↔ "${t[j][0]}"`);
    }
  });
  return r;
}"""


def main():
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("RENDER_AUDIT_NOT_RUN: playwright 미설치")
        return 2
    base = sys.argv[sys.argv.index("--base") + 1] if "--base" in sys.argv else None
    engine = sys.argv[sys.argv.index("--browser") + 1] if "--browser" in sys.argv else "chromium"
    course = json.load(open(os.path.join(ROOT, "course.json"), encoding="utf-8"))
    pages = ["index.html"] + [c["file"] for c in course["chapters"] if os.path.exists(os.path.join(ROOT, c["file"]))]
    url = (lambda p: base.rstrip("/") + "/" + p) if base else (lambda p: "file://" + os.path.join(ROOT, p))
    rows, fails = [], 0
    with sync_playwright() as pw:
        b = getattr(pw, engine).launch()
        ver = b.version
        # 클립보드 읽기 권한은 Chromium에서만 부여할 수 있어 복사 원문 비교는 Chromium 전용
        ctx = b.new_context(permissions=["clipboard-read", "clipboard-write"]) if engine == "chromium" else b.new_context()
        pg = ctx.new_page()
        for p in pages:
            issues, info = [], {}
            for w in WIDTHS:
                pg.set_viewport_size({"width": w, "height": 900})
                resp = pg.goto(url(p))
                if base and (resp is None or resp.status != 200):
                    issues.append(f"HTTP {resp.status if resp else '없음'}")
                    break
                pg.wait_for_timeout(250)
                r = pg.evaluate(JS_PAGE)
                info = r if w == 1366 else info
                if r["overflow"] > 1:
                    issues.append(f"{w}px 가로 넘침 {r['overflow']}px")
                if w == 1366 and not (150 <= (r["hero_h"] or 0) <= 230):
                    issues.append(f"헤더 높이 {r['hero_h']}px")
                if w == 390 and p != "index.html":
                    pg.click("#mobile-menu")
                    opened = pg.evaluate("document.getElementById('course-nav').classList.contains('open')")
                    pg.keyboard.press("Escape")
                    closed = not pg.evaluate("document.getElementById('course-nav').classList.contains('open')")
                    if not (opened and closed):
                        issues.append("모바일 메뉴 열기/Escape 닫기 실패")
            if issues and issues[0].startswith("HTTP"):
                rows.append((p, "실패", issues[0])); fails += 1; continue
            if not info.get("hero_img"):
                issues.append("책장 사진 미적용")
            if info.get("paper") != "rgb(241, 242, 238)":
                issues.append(f"바탕색 {info.get('paper')}")
            if p != "index.html":
                if info["nav_chapters"] < len(pages) - 1:
                    issues.append(f"탐색 장 링크 {info['nav_chapters']}개")
                if len(info["links"]) != 2:
                    issues.append("이전/다음 링크 없음")
                for h in info["links"]:
                    if h and not h.startswith("http") and not os.path.exists(os.path.join(ROOT, h)):
                        issues.append(f"깨진 이전/다음 링크 {h}")
                if info["copy_buttons"] != info["codeblocks"]:
                    issues.append(f"복사 버튼 {info['copy_buttons']}/{info['codeblocks']}")
                # 첫 실제 소스 코드 박스 복사 결과가 pre 원문과 같은지
                pg.set_viewport_size({"width": 1366, "height": 900})
                pg.goto(url(p)); pg.wait_for_timeout(250)
                blocks = pg.locator(".codeblock").filter(has_text=".v · verilog")
                if blocks.count() and engine == "chromium":
                    blk = blocks.first
                    blk.locator(".codebar button").click()
                    pg.wait_for_timeout(150)
                    got = pg.evaluate("navigator.clipboard.readText()")
                    want = blk.locator("pre").inner_text()
                    if got.rstrip("\n") != want.rstrip("\n"):
                        issues.append("코드 복사 내용 불일치")
                issues += [f"SVG 글자 겹침 {x}" for x in info["svg_overlaps"]]
                issues += [f"SVG 글자 잘림 {x}" for x in info["svg_clipped"]]
            ok = not issues
            fails += not ok
            note = (f"헤더 {info.get('hero_h')}px · 코드 박스 {info.get('codeblocks')}" if ok else "; ".join(issues))
            rows.append((p, "통과" if ok else "실패", note))
        b.close()
    target = base or "로컬 파일"
    out = ["# 화면 점검 결과 (자동 생성)", "",
           f"`python3 tools/guide/audit_render.py{' --base ' + base if base else ''}{' --browser ' + engine if engine != 'chromium' else ''}` · 대상: {target} · {engine} {ver} (Playwright)", "",
           f"검사: 화면 폭 {'·'.join(map(str, WIDTHS))}px 가로 넘침, 헤더 높이(1366px), 책장 사진·바탕색, 장 탐색, 이전/다음 링크, "
           "390px 모바일 메뉴 열기·Escape 닫기, 코드 복사 버튼 수, " + ("첫 Verilog 박스 복사 원문 일치, " if engine == "chromium" else "") + "SVG 글자 겹침", "",
           "| 페이지 | 판정 | 근거 |", "|---|---|---|"] + [f"| {p} | {r} | {n} |" for p, r, n in rows]
    out += ["", "다른 브라우저 결과: `docs/RENDER_AUDIT*_firefox.md`·`*_webkit.md`. 인쇄·접근성: `docs/A11Y_PRINT_AUDIT.md`."]
    name = ("RENDER_AUDIT_PAGES" if base else "RENDER_AUDIT") + ("" if engine == "chromium" else "_" + engine) + ".md"
    open(os.path.join(ROOT, "docs", name), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(("RENDER_AUDIT_PASS" if not fails else f"RENDER_AUDIT_FAIL count={fails}") + f" pages={len(rows)}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
