const normalize = (value) =>
  String(value ?? "").replace(/\s+/g, " ").trim();

const escapeHTML = (value) =>
  String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");

const logo = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
    <stop stop-color="#fb923c"/><stop offset="1" stop-color="#4f46e5"/>
  </linearGradient></defs>
  <rect width="512" height="512" rx="112" fill="#090d2c"/>
  <rect x="40" y="40" width="432" height="432" rx="88" fill="url(#g)" opacity=".22"/>
  <path d="M218 157c0-22 24-35 43-24l151 88c19 11 19 38 0 49l-151 88c-19 11-43-3-43-25z" fill="#fff"/>
  <circle cx="150" cy="256" r="54" fill="#fb923c"/>
</svg>`;

const sharePage = (url, movieID) => {
  const title = normalize(url.searchParams.get("title")).slice(0, 120) ||
    `电影 #${movieID}`;
  const year = normalize(url.searchParams.get("year")).slice(0, 12);
  const rating = normalize(url.searchParams.get("rating")).slice(0, 8);
  const summary = normalize(url.searchParams.get("summary")).slice(0, 240) ||
    "在 CineBar 发现这部电影。";
  const posterPath = normalize(url.searchParams.get("poster"));
  const poster = /^\/[A-Za-z0-9._/-]+$/.test(posterPath)
    ? `https://image.tmdb.org/t/p/w500${posterPath}`
    : `${url.origin}/cinebar-logo.svg`;
  const pageURL = escapeHTML(url.href);

  return new Response(`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${escapeHTML(title)} · CineBar</title>
  <meta name="description" content="${escapeHTML(summary)}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="CineBar">
  <meta property="og:title" content="${escapeHTML(title)} · CineBar">
  <meta property="og:description" content="${escapeHTML(summary)}">
  <meta property="og:image" content="${escapeHTML(poster)}">
  <meta property="og:url" content="${pageURL}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapeHTML(title)} · CineBar">
  <meta name="twitter:description" content="${escapeHTML(summary)}">
  <meta name="twitter:image" content="${escapeHTML(poster)}">
  <style>
    :root{color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
    *{box-sizing:border-box}body{margin:0;min-height:100vh;color:#f8fafc;
    background:radial-gradient(circle at 80% 10%,#f59e0b38,transparent 34rem),
    linear-gradient(145deg,#070a24,#11183f 55%,#080b22);display:grid;place-items:center;padding:28px}
    main{width:min(900px,100%)}header{display:flex;align-items:center;gap:14px;margin-bottom:24px}
    .logo{width:62px;height:62px;border-radius:15px;box-shadow:0 12px 40px #0008}
    .brand{font-size:30px;font-weight:800}.tagline{color:#a9b4d0}
    .card{display:grid;grid-template-columns:minmax(190px,290px) 1fr;gap:34px;padding:28px;
    border:1px solid #ffffff1f;border-radius:28px;background:#ffffff0d;backdrop-filter:blur(22px);
    box-shadow:0 28px 90px #0008}.poster{width:100%;aspect-ratio:2/3;object-fit:cover;
    border-radius:18px;background:#ffffff0b;box-shadow:0 20px 50px #0009}
    .content{align-self:center}h1{font-size:clamp(32px,6vw,60px);line-height:1.05;margin:0 0 14px}
    .meta{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:22px}.pill{padding:7px 11px;
    border-radius:999px;background:#ffffff12;color:#d8def0}.rating{color:#ffd36a}
    p{color:#c2cae0;font-size:18px;line-height:1.7}.from{margin-top:30px;color:#7f8caf;font-size:14px}
    @media(max-width:650px){.card{grid-template-columns:1fr;padding:20px}.poster{max-width:280px;margin:auto}}
  </style>
</head>
<body><main><header><img class="logo" src="/cinebar-logo.svg" alt="CineBar">
<div><div class="brand">CineBar</div><div class="tagline">今晚看什么？</div></div></header>
<section class="card"><img class="poster" src="${escapeHTML(poster)}" alt="${escapeHTML(title)} 海报">
<div class="content"><h1>${escapeHTML(title)}</h1><div class="meta">
${year ? `<span class="pill">${escapeHTML(year)}</span>` : ""}
${rating ? `<span class="pill rating">★ ${escapeHTML(rating)} / 10</span>` : ""}
</div><p>${escapeHTML(summary)}</p><div class="from">由 CineBar for macOS 分享</div>
</div></section></main></body></html>`, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=3600",
      "x-content-type-options": "nosniff",
    },
  });
};

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/updates/latest.json") {
      return new Response(JSON.stringify({
        version: "0.8.1",
        build: 13,
        published_at: "2026-07-27",
        download_url: null,
        notes: [
          "匿名评分改为每部作品只能提交一次",
          "修复评分滑块与可移动窗口的拖动冲突",
          "修复双显示器菜单栏面板定位",
          "放大并强化电影与电视剧分级显示",
        ],
      }), {
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "public, max-age=300",
        },
      });
    }
    if (url.pathname === "/cinebar-logo.svg") {
      return new Response(logo, {
        headers: {
          "content-type": "image/svg+xml; charset=utf-8",
          "cache-control": "public, max-age=86400",
        },
      });
    }
    const match = url.pathname.match(/^\/share\/movies\/(\d+)\/?$/);
    if (request.method === "GET" && match) {
      return sharePage(url, Number(match[1]));
    }
    return new Response("CineBar Share is running.", {
      status: url.pathname === "/" ? 200 : 404,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  },
};
