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

export const mediaPath = (pathname) => {
  const match = pathname.match(/^\/(m|t)\/([1-9]\d*)\/?$/);
  if (!match) return null;
  return {
    mediaType: match[1] === "m" ? "movie" : "tv",
    mediaID: Number(match[2]),
  };
};

const canonicalPath = (mediaType, mediaID) =>
  `/${mediaType === "movie" ? "m" : "t"}/${mediaID}`;

const validatedDownloadURL = (value) => {
  try {
    const url = new URL(normalize(value));
    return url.protocol === "https:" ? url.href : null;
  } catch {
    return null;
  }
};

const healthResponse = (service) =>
  new Response(
    JSON.stringify({
      ok: true,
      service,
      version: "0.8.3-test.7",
      utc: new Date().toISOString(),
    }),
    {
      headers: {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
        "x-content-type-options": "nosniff",
      },
    },
  );

const rootPage = () =>
  new Response(`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>CineBar — 找到下一部好片</title>
  <meta name="description" content="CineBar 是一款面向 macOS 的电影与电视剧发现工具。">
  <style>
    :root{color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
    *{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;
    padding:28px;color:#f8fafc;background:radial-gradient(circle at 75% 15%,#f59e0b38,
    transparent 30rem),linear-gradient(145deg,#070a24,#11183f 55%,#080b22)}
    main{width:min(760px,100%);padding:42px;border:1px solid #ffffff1f;border-radius:30px;
    background:#ffffff0d;backdrop-filter:blur(22px);box-shadow:0 28px 90px #0008}
    header{display:flex;align-items:center;gap:16px}.logo{width:70px;height:70px;border-radius:18px}
    h1{font-size:clamp(42px,9vw,82px);margin:34px 0 12px;letter-spacing:-.05em}
    .tagline{font-size:24px;color:#ffd36a}.summary{max-width:620px;color:#c2cae0;
    font-size:18px;line-height:1.75;margin:24px 0 0}.status{display:inline-flex;margin-top:30px;
    padding:8px 12px;border-radius:999px;background:#34d39920;color:#86efac}
  </style>
</head>
<body><main><header><img class="logo" src="/cinebar-logo.svg" alt="CineBar">
<strong>CineBar</strong></header><h1>找到下一部好片</h1>
<div class="tagline">电影与电视剧发现工具</div>
<p class="summary">在 macOS 菜单栏中发现热门作品、查看评分与演职员信息，并保存自己的片单。</p>
<div class="status">cinebar.cc 已启用</div></main></body></html>`, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300",
      "x-content-type-options": "nosniff",
    },
  });

const loadTMDBJSON = async (endpoint, env) => {
  const fetcher = env.MEDIA_FETCHER ?? fetch;
  const response = await fetcher(endpoint.href, {
    headers: {
      accept: "application/json",
      authorization: `Bearer ${env.TMDB_BEARER_TOKEN}`,
    },
  });
  if (!response.ok) {
    throw new Error(`TMDB request failed with ${response.status}`);
  }
  return response.json();
};

const loadMetadata = async (route, env) => {
  if (!normalize(env.TMDB_BEARER_TOKEN)) {
    throw new Error("TMDB bearer token is not configured");
  }
  const basePath = `${route.mediaType}/${route.mediaID}`;
  const detailsURL = new URL(`https://api.themoviedb.org/3/${basePath}`);
  detailsURL.searchParams.set("language", "zh-CN");
  const payload = await loadTMDBJSON(detailsURL, env);

  const creditsURL = new URL(
    `https://api.themoviedb.org/3/${basePath}/credits`,
  );
  creditsURL.searchParams.set("language", "zh-CN");
  let credits = { cast: [] };
  try {
    credits = await loadTMDBJSON(creditsURL, env);
  } catch {
    credits = { cast: [] };
  }

  const isMovie = route.mediaType === "movie";
  return {
    title: normalize(isMovie ? payload.title : payload.name).slice(0, 120),
    year: normalize(
      isMovie ? payload.release_date : payload.first_air_date,
    ).slice(0, 4),
    rating: Number.isFinite(Number(payload.vote_average))
      ? Number(payload.vote_average).toFixed(1)
      : "",
    summary: normalize(payload.overview).slice(0, 240),
    posterPath: normalize(payload.poster_path),
    cast: Array.isArray(credits.cast)
      ? credits.cast.slice(0, 6).map((member) => ({
        name: normalize(member.name).slice(0, 80),
        character: normalize(member.character).slice(0, 100),
      })).filter((member) => member.name)
      : [],
  };
};

const sharePage = (url, route, metadata, downloadURL) => {
  const isMovie = route.mediaType === "movie";
  const fallbackTitle = `${isMovie ? "电影" : "电视剧"} #${route.mediaID}`;
  const title = metadata?.title || fallbackTitle;
  const year = metadata?.year || "";
  const rating = metadata?.rating || "";
  const summary = metadata?.summary ||
    (metadata
      ? `在 CineBar 发现这部${isMovie ? "电影" : "电视剧"}。`
      : "影片资料暂时无法加载，请稍后再试。");
  const cast = metadata?.cast ?? [];
  const brandedTitle = `《${title}》— CineBar`;
  const castSummary = cast.map((member) => member.name).join("、");
  const socialDescription = normalize(
    `${castSummary ? `主演：${castSummary}。` : ""}${summary}`,
  ).slice(0, 300);
  const posterPath = metadata?.posterPath || "";
  const poster = /^\/[A-Za-z0-9._/-]+$/.test(posterPath)
    ? `https://image.tmdb.org/t/p/w500${posterPath}`
    : `${url.origin}/cinebar-logo.svg`;
  const pageURL = escapeHTML(
    `${url.origin}${canonicalPath(route.mediaType, route.mediaID)}`,
  );
  const safeDownloadURL = validatedDownloadURL(downloadURL);
  const downloadBlock = safeDownloadURL
    ? `<a class="download" href="${escapeHTML(safeDownloadURL)}">查看 CineBar 版本与下载</a>`
    : "";
  const castBlock = cast.length
    ? `<section class="cast"><h2>主要演员</h2><div class="cast-list">${
      cast.map((member) =>
        `<div class="cast-member"><strong>${escapeHTML(member.name)}</strong>${
          member.character
            ? `<span>饰 ${escapeHTML(member.character)}</span>`
            : ""
        }</div>`
      ).join("")
    }</div></section>`
    : "";

  return new Response(`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${escapeHTML(brandedTitle)}</title>
  <meta name="description" content="${escapeHTML(socialDescription)}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="CineBar">
  <meta property="og:title" content="${escapeHTML(brandedTitle)}">
  <meta property="og:description" content="${escapeHTML(socialDescription)}">
  <meta property="og:image" content="${escapeHTML(poster)}">
  <meta property="og:url" content="${pageURL}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapeHTML(brandedTitle)}">
  <meta name="twitter:description" content="${escapeHTML(socialDescription)}">
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
    .download{display:inline-flex;margin-top:22px;padding:11px 16px;border-radius:12px;
    background:#f59e0b;color:#111827;text-decoration:none;font-weight:750}
    .cast{margin-top:24px}.cast h2{font-size:16px;margin:0 0 10px;color:#f8fafc}
    .cast-list{display:grid;gap:8px}.cast-member{display:flex;gap:8px;flex-wrap:wrap;
    color:#d8def0}.cast-member span{color:#a9b4d0}
    @media(max-width:650px){.card{grid-template-columns:1fr;padding:20px}.poster{max-width:280px;margin:auto}}
  </style>
</head>
<body><main><header><img class="logo" src="/cinebar-logo.svg" alt="CineBar">
<div><div class="brand">CineBar</div><div class="tagline">找到下一部好片</div></div></header>
<section class="card"><img class="poster" src="${escapeHTML(poster)}" alt="${escapeHTML(title)} 海报">
<div class="content"><h1>${escapeHTML(title)}</h1><div class="meta">
${year ? `<span class="pill">${escapeHTML(year)}</span>` : ""}
${rating ? `<span class="pill rating">★ ${escapeHTML(rating)} / 10</span>` : ""}
</div><p>${escapeHTML(summary)}</p>${castBlock}${downloadBlock}<div class="from">由 CineBar for macOS 分享</div>
</div></section></main></body></html>`, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=3600",
      "x-content-type-options": "nosniff",
    },
  });
};

export default {
  async fetch(request, env = {}) {
    const url = new URL(request.url);
    if (url.protocol === "http:") {
      url.protocol = "https:";
      return Response.redirect(url.toString(), 308);
    }
    if (request.method === "GET" && url.pathname === "/health") {
      return healthResponse("cinebar-share");
    }
    if (request.method === "GET" && url.pathname === "/") {
      return rootPage();
    }
    if (url.pathname === "/updates/latest.json") {
      return new Response(JSON.stringify({
        version: "0.8.3-test.7",
        build: 23,
        published_at: "2026-08-03",
        download_url: "https://github.com/leeugm-create/CineBar/releases",
        notes: [
          "新增本地片库：选择文件夹后可刷新扫描，新影片自动加入",
          "本地播放依次尝试 IINA、VLC 和 macOS 系统默认播放器",
          "TMDB 匹配需要确认；本地文件不上传，也不提供盗版或下载资源",
          "Build 23 当前请从 GitHub Releases 手动安装；已签名 appcast 发布后才支持应用内更新",
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
    const route = mediaPath(url.pathname);
    if (request.method === "GET" && route) {
      let metadata = null;
      try {
        metadata = await loadMetadata(route, env);
      } catch {
        metadata = null;
      }
      return sharePage(
        url,
        route,
        metadata,
        env.CINEBAR_DOWNLOAD_URL,
      );
    }
    return new Response("Not found.", {
      status: 404,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  },
};
