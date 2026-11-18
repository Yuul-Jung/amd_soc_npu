#!/usr/bin/env python3
"""학습안내서 인쇄·접근성 점검 (rule_md STANDARD 10.2·10.4).

  python3 tools/guide/audit_a11y_print.py --axe <axe.min.js 경로>
      (npm install axe-core → node_modules/axe-core/axe.min.js)
결과: docs/A11Y_PRINT_AUDIT.md

인쇄: Chromium으로 A4 PDF를 만들고 pdftotext로 꺼낸 글에
      ① 각 코드 박스의 마지막 줄이 모두 들어 있는지(잘림 없음) ② 좌측 탐색 문구가 없는지 확인한다.
접근성: axe-core WCAG 2.0/2.1 A·AA 규칙 자동 검사. 위반 0건이면 통과.
      자동 검사는 실제 스크린리더 낭독을 대신하지 않는다(별도 미검증).
"""
import json, os, re, subprocess, sys, tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def norm(s):
    return re.sub(r"\s+", "", s)


def main():
    axe = sys.argv[sys.argv.index("--axe") + 1] if "--axe" in sys.argv else None
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("A11Y_PRINT_AUDIT_NOT_RUN: playwright 미설치")
        return 2
    course = json.load(open(os.path.join(ROOT, "course.json"), encoding="utf-8"))
    pages = ["index.html"] + [c["file"] for c in course["chapters"] if os.path.exists(os.path.join(ROOT, c["file"]))]
    rows, fails = [], 0
    with sync_playwright() as pw:
        b = pw.chromium.launch()
        pg = b.new_page(viewport={"width": 1366, "height": 900})
        for p in pages:
            pg.goto("file://" + os.path.join(ROOT, p))
            pg.wait_for_timeout(300)
            # ── 인쇄 ──
            last_lines = pg.evaluate("""() => [...document.querySelectorAll('.codeblock pre')]
                .map(p => p.textContent.split('\\n').map(s => s.trim()).filter(Boolean).pop() || '')""")
            with tempfile.TemporaryDirectory() as d:
                pdf = os.path.join(d, "p.pdf")
                pg.emulate_media(media="print")
                pg.pdf(path=pdf, format="A4", margin={"top": "12mm", "bottom": "12mm", "left": "12mm", "right": "12mm"})
                pg.emulate_media(media="screen")
                txt = subprocess.run(["pdftotext", "-layout", pdf, "-"], capture_output=True, text=True).stdout
                npages = subprocess.run(["pdfinfo", pdf], capture_output=True, text=True).stdout
                npages = re.search(r"Pages:\s+(\d+)", npages).group(1)
            flat = norm(txt)
            missing = [l for l in last_lines if l and norm(l)[:60] not in flat]
            nav_left = "전체장바로가기" in flat
            pissues = ([f"코드 끝줄 누락 {len(missing)}/{len(last_lines)}"] if missing else []) + (["좌측 탐색 인쇄됨"] if nav_left else [])
            # ── 접근성 ──
            aissues, anote = [], "axe 미실행"
            if axe:
                pg.add_script_tag(path=axe)
                res = pg.evaluate("""async () => { const r = await axe.run(document, {runOnly: {type: 'tag', values: ['wcag2a','wcag2aa','wcag21a','wcag21aa']}});
                    return {v: r.violations.map(v => [v.id, v.impact, v.nodes.length]), p: r.passes.length}; }""")
                aissues = [f"{i}({imp}, {n}곳)" for i, imp, n in res["v"]]
                anote = f"axe 통과 규칙 {res['p']}개"
            ok = not pissues and not aissues
            fails += not ok
            rows.append((p, "통과" if ok else "실패",
                         f"PDF {npages}쪽 · 코드 끝줄 {len(last_lines) - len(missing)}/{len(last_lines)} · {anote}" if ok
                         else "; ".join(pissues + aissues)))
        ver = b.version
        b.close()
    out = ["# 인쇄·접근성 점검 결과 (자동 생성)", "",
           f"`python3 tools/guide/audit_a11y_print.py --axe …` · Chromium {ver} · A4 PDF + pdftotext · axe-core WCAG 2.0/2.1 A·AA", "",
           "| 페이지 | 판정 | 근거 |", "|---|---|---|"] + [f"| {p} | {r} | {n} |" for p, r, n in rows]
    out += ["", "미검증: 실제 스크린리더(NVDA·VoiceOver) 낭독, 종이 인쇄 결과물."]
    open(os.path.join(ROOT, "docs", "A11Y_PRINT_AUDIT.md"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(("A11Y_PRINT_AUDIT_PASS" if not fails else f"A11Y_PRINT_AUDIT_FAIL count={fails}") + f" pages={len(rows)}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
