/*
 * 교육용 HTML 공통 동작 — 유지보수용 원본 (STANDARD 4·10.3·10.4)
 * 페이지 본문은 바꾸지 않고 탐색·이전/다음·모바일 메뉴·코드 복사만 덧붙인다.
 * 입력: 페이지의 window.COURSE (tools/guide/build_guides.py가 실제 존재하는 장만 넣음),
 *       body[data-chapter], main section[id] > h2.
 * 이관 원본과 구문 트리(acorn AST)가 같음을 확인함.
 */
(() => {
  "use strict";
  const data = window.COURSE || { title: "교육과정", chapters: [] };
  const nav = document.getElementById("course-nav");
  if (!nav) return;
  const current = document.body.dataset.chapter || "";
  const pageNames = data.chapters || [];
  // 1. 좌측 탐색: INDEX 링크와 전체 장 목록 (현재 장 표시·aria-current)
  const home = document.createElement("a");
  home.className = "toplink";
  home.href = "index.html";
  home.textContent = "⌂ " + data.title;
  nav.append(home);
  let h = document.createElement("h2");
  h.textContent = "전체 장 바로가기";
  nav.append(h);
  const ul = document.createElement("ul");
  pageNames.forEach((ch) => {
    let li = document.createElement("li"),
      a = document.createElement("a");
    a.href = ch.file;
    a.textContent = String(ch.number).padStart(2, "0") + "  " + ch.title;
    if (ch.id === current) {
      a.className = "current-chapter active";
      a.setAttribute("aria-current", "page");
    }
    li.append(a);
    ul.append(li);
  });
  nav.append(ul);

  // 2. 현재 페이지 목차: 절 제목(h2)을 모으고, 화면에 보이는 절을 강조
  const sections = [...document.querySelectorAll("main section[id]")];
  if (sections.length) {
    h = document.createElement("h2");
    h.textContent = "현재 페이지 목차";
    nav.append(h);
    const sub = document.createElement("ul");
    sub.className = "toc-sections";
    sections.forEach((sec) => {
      let li = document.createElement("li"),
        a = document.createElement("a");
      a.href = "#" + sec.id;
      a.textContent = sec.querySelector("h2")?.textContent.trim().replace(/\s+/g, " ") || sec.id;
      li.append(a);
      sub.append(li);
    });
    nav.append(sub);
    if ("IntersectionObserver" in window) {
      const obs = new IntersectionObserver(
        (entries) => {
          const visible = entries
            .filter((e) => e.isIntersecting)
            .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
          if (visible[0]) {
            sub
              .querySelectorAll("a")
              .forEach((x) =>
                x.classList.toggle("active", x.getAttribute("href") === "#" + visible[0].target.id),
              );
          }
        },
        { rootMargin: "-10% 0px -68% 0px", threshold: 0 },
      );
      sections.forEach((x) => obs.observe(x));
    }
  }

  // 3. 본문 끝 이전/다음 장 링크 (처음·마지막 장은 전체 목차로)
  const idx = pageNames.findIndex((ch) => ch.id === current);
  const links = document.getElementById("chapter-links");
  if (links && idx >= 0) {
    const prev = pageNames[idx - 1],
      next = pageNames[idx + 1];
    const add = (ch, label) => {
      let a = document.createElement("a");
      a.href = ch?.file || "index.html";
      a.textContent = label + (ch ? " · " + ch.title : " · 전체 목차");
      links.append(a);
    };
    add(prev, "← 이전");
    add(next, "다음 →");
  }

  // 4. 모바일 서랍 메뉴: 버튼·덮개 클릭, 링크 선택, Escape 키로 닫기
  const toggle = document.getElementById("mobile-menu"),
    shade = document.getElementById("shade");
  const close = () => {
    nav.classList.remove("open");
    shade?.classList.remove("open");
    toggle?.setAttribute("aria-expanded", "false");
  };
  toggle?.addEventListener("click", () => {
    let open = !nav.classList.contains("open");
    nav.classList.toggle("open", open);
    shade?.classList.toggle("open", open);
    toggle.setAttribute("aria-expanded", String(open));
  });
  shade?.addEventListener("click", close);
  nav.addEventListener("click", (e) => {
    if (e.target.closest("a")) close();
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") close();
  });

  // 5. 코드 박스 복사 버튼: pre의 소스 텍스트만 복사 (제목 줄 제외)
  document.querySelectorAll(".codeblock").forEach((block) => {
    const pre = block.querySelector("pre");
    if (!pre) return;
    const bar = block.querySelector(".codebar");
    if (!bar) return;
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = "복사";
    b.setAttribute("aria-label", "코드 복사");
    b.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(pre.textContent);
        b.textContent = "복사 완료";
        setTimeout(() => (b.textContent = "복사"), 1200);
      } catch {
        b.textContent = "복사 실패";
      }
    });
    bar.append(b);
  });
})();
