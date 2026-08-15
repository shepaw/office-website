const I18N = {
  zh: {
    nav_docs: "文档",
    nav_download: "下载",
    nav_github: "GitHub",
    nav_get: "开始使用",
    lang: "EN",
    footer_product: "产品",
    footer_docs: "文档",
    footer_community: "社区",
    footer_blurb:
      "Shepaw 是本地优先的 Agent 中枢：手机与桌面调度 Claude Code、Gemini、Qwen Code、Copilot 等 40+ 原生引擎。Channel 只转发密文。",
    footer_copy: "开源 · 本地优先 · 端到端加密",
  },
  en: {
    nav_docs: "Docs",
    nav_download: "Download",
    nav_github: "GitHub",
    nav_get: "Get started",
    lang: "中文",
    footer_product: "Product",
    footer_docs: "Docs",
    footer_community: "Community",
    footer_blurb:
      "Shepaw is a local-first agent hub: drive Claude Code, Gemini, Qwen Code, Copilot, and 40+ native engines from your phone or desktop. Channel only relays ciphertext.",
    footer_copy: "Open source · Local-first · End-to-end encrypted",
  },
};

const DOCS_NAV = [
  { group: { zh: "开始", en: "Start" } },
  { href: "/docs/", key: "start", zh: "快速开始", en: "Getting started" },
  { href: "/docs/pairing.html", key: "pairing", zh: "扫码配对", en: "Pairing" },
  { href: "/docs/app.html", key: "app", zh: "App 功能", en: "App" },
  { group: { zh: "本机 Agent", en: "On your machine" } },
  { href: "/docs/hub.html", key: "hub", zh: "Agent Hub", en: "Agent Hub" },
  { href: "/docs/engines.html", key: "engines", zh: "引擎", en: "Engines" },
  { href: "/docs/cli.html", key: "cli", zh: "CLI 参考", en: "CLI" },
  { group: { zh: "连接与安全", en: "Connect & security" } },
  { href: "/docs/channel.html", key: "channel", zh: "Channel 与隧道", en: "Channel" },
  { href: "/docs/security.html", key: "security", zh: "安全模型", en: "Security" },
  { href: "/docs/self-host.html", key: "selfhost", zh: "自托管", en: "Self-host" },
  { href: "/docs/faq.html", key: "faq", zh: "FAQ", en: "FAQ" },
];

function lang() {
  return localStorage.getItem("shepaw-lang") === "en" ? "en" : "zh";
}

function setLang(next) {
  localStorage.setItem("shepaw-lang", next);
  applyLang();
}

function applyLang() {
  const l = lang();
  document.documentElement.lang = l === "en" ? "en" : "zh-CN";
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    const dict = I18N[l];
    if (dict[key]) el.textContent = dict[key];
  });
  document.querySelectorAll("[data-zh],[data-en]").forEach((el) => {
    const text = el.getAttribute(l === "en" ? "data-en" : "data-zh");
    if (text != null) el.innerHTML = text;
  });
  document.querySelectorAll(".lang-zh").forEach((el) => {
    el.hidden = l !== "zh";
  });
  document.querySelectorAll(".lang-en").forEach((el) => {
    el.hidden = l !== "en";
  });
  renderChrome();
}

function headerHTML() {
  const t = I18N[lang()];
  const page = document.body.dataset.page;
  return `
    <header class="site-header">
      <div class="wrap nav">
        <a class="brand" href="/">
          <img src="/assets/img/logo.png" alt="Shepaw">
          Shepaw
        </a>
        <nav class="nav-links">
          <a href="/docs/" class="${page === "docs" ? "is-active" : ""}">${t.nav_docs}</a>
          <a href="/download/" class="${page === "download" ? "is-active" : ""}">${t.nav_download}</a>
          <a href="https://github.com/shepaw/shepaw" target="_blank" rel="noreferrer">${t.nav_github}</a>
          <button class="lang" type="button" data-toggle-lang>${t.lang}</button>
          <a class="nav-cta" href="/download/">${t.nav_get}</a>
        </nav>
        <button class="nav-toggle" type="button" aria-label="Menu">☰</button>
      </div>
    </header>
    <div class="mobile-nav">
      <a href="/docs/">${t.nav_docs}</a>
      <a href="/download/">${t.nav_download}</a>
      <a href="https://github.com/shepaw/shepaw" target="_blank" rel="noreferrer">${t.nav_github}</a>
      <button type="button" data-toggle-lang>${t.lang}</button>
      <a href="/download/">${t.nav_get}</a>
    </div>
  `;
}

function footerHTML() {
  const t = I18N[lang()];
  const l = lang();
  return `
    <footer class="site-footer">
      <div class="wrap footer-grid">
        <div>
          <a class="brand" href="/" style="margin-bottom:12px">
            <img src="/assets/img/logo.png" alt=""> Shepaw
          </a>
          <p>${t.footer_blurb}</p>
        </div>
        <div>
          <h4>${t.footer_product}</h4>
          <a href="/download/">${t.nav_download}</a>
          <a href="/docs/">${l === "en" ? "Getting started" : "快速开始"}</a>
          <a href="/docs/hub.html">Agent Hub</a>
          <a href="/docs/channel.html">Channel</a>
        </div>
        <div>
          <h4>${t.footer_docs}</h4>
          <a href="/docs/pairing.html">${l === "en" ? "Pairing" : "扫码配对"}</a>
          <a href="/docs/security.html">${l === "en" ? "Security" : "安全模型"}</a>
          <a href="/docs/cli.html">CLI</a>
          <a href="/docs/faq.html">FAQ</a>
        </div>
        <div>
          <h4>${t.footer_community}</h4>
          <a href="https://github.com/shepaw/shepaw" target="_blank" rel="noreferrer">shepaw/shepaw</a>
          <a href="https://github.com/shepaw/agent-bridge" target="_blank" rel="noreferrer">shepaw/agent-bridge</a>
          <a href="/docs/self-host.html">Channel</a>
        </div>
      </div>
      <div class="wrap footnote">
        <span>${t.footer_copy}</span>
        <span>shepaw.com</span>
      </div>
    </footer>
  `;
}

function docsNavHTML() {
  const l = lang();
  const current = document.body.dataset.doc;
  return DOCS_NAV.map((item) => {
    if (item.group) {
      return `<div class="group">${item.group[l]}</div>`;
    }
    return `<a href="${item.href}" class="${current === item.key ? "is-active" : ""}">${item[l]}</a>`;
  }).join("");
}

function renderChrome() {
  let header = document.getElementById("site-chrome-header");
  if (!header) {
    header = document.createElement("div");
    header.id = "site-chrome-header";
    document.body.prepend(header);
  }
  header.innerHTML = headerHTML();

  let footer = document.getElementById("site-chrome-footer");
  if (!footer) {
    footer = document.createElement("div");
    footer.id = "site-chrome-footer";
    document.body.append(footer);
  }
  footer.innerHTML = footerHTML();

  const docsNav = document.getElementById("docs-nav");
  if (docsNav) docsNav.innerHTML = docsNavHTML();

  document.querySelectorAll("[data-toggle-lang]").forEach((btn) => {
    btn.addEventListener("click", () => setLang(lang() === "zh" ? "en" : "zh"));
  });
  document.querySelector(".nav-toggle")?.addEventListener("click", () => {
    document.body.classList.toggle("nav-open");
  });
}

function enhanceCode() {
  document.querySelectorAll("pre[data-copy], .cli").forEach((block) => {
    if (block.dataset.enhanced) return;
    block.dataset.enhanced = "1";
    const pre = block.tagName === "PRE" ? block : block.querySelector("pre");
    if (!pre) return;
    const btn = document.createElement("button");
    btn.className = "copy-btn";
    btn.type = "button";
    btn.textContent = "Copy";
    btn.addEventListener("click", async () => {
      await navigator.clipboard.writeText(pre.innerText);
      btn.textContent = "Copied";
      setTimeout(() => (btn.textContent = "Copy"), 1200);
    });
    if (block.classList.contains("cli")) {
      const bar = block.querySelector(".cli-bar");
      if (bar && !bar.querySelector(".copy-btn")) bar.append(btn);
    } else {
      pre.style.position = "relative";
      btn.style.position = "absolute";
      btn.style.right = "10px";
      btn.style.top = "10px";
      pre.prepend(btn);
    }
  });
}

document.addEventListener("DOMContentLoaded", () => {
  applyLang();
  enhanceCode();
});
