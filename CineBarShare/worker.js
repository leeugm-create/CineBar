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

// ---------------------------------------------------------------------------
// Moovie (moovie.c2v2.com) 在线正片源解析。与 macOS 版 CineBar 共用同一套
// 搜索接口与播放页结构：搜索接口返回多家资源源的播放页链接，播放页内嵌
// HLS (m3u8) 直链。m3u8 CDN 返回 access-control-allow-origin: *，网页端
// 可直接用 hls.js 播放，无需代理。
// ---------------------------------------------------------------------------

const MOOVIE_BASE = "https://moovie.c2v2.com";
const MOOVIE_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

const moovieFetch = async (path, timeoutMs = 25000, retries = 2) => {
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(`${MOOVIE_BASE}${path}`, {
        headers: {
          "user-agent": MOOVIE_UA,
          accept: "text/html,application/xhtml+xml",
        },
        signal: controller.signal,
      });
      if (!response.ok) return null;
      return await response.text();
    } catch {
      if (attempt === retries) return null;
    } finally {
      clearTimeout(timer);
    }
  }
  return null;
};

const isDerivativeTitle = (title) =>
  /解说|预告|花絮/.test(title);

/** 按片名+年份搜索可播放的正片源（解析逻辑与 App 端 parseSearchResults 一致）。 */
const moovieSearch = async (title, year) => {
  const query = normalize(title);
  if (!query) return [];
  const params = new URLSearchParams({ kw: query });
  if (year) params.set("year", year);
  const html = await moovieFetch(`/api/htmx/search?${params}`);
  if (!html) return [];
  return moovieParseResults(html, query);
};

/** 从搜索接口返回的 HTML 解析候选源列表（离线纯函数）。 */
const moovieParseResults = (html, query) => {
  const results = [];
  const pattern = /href="(\/play\/[^"]+)"[^>]*class="search-result-card"[\s\S]*?card-title">([^<]+)<\/h3>[\s\S]*?card-year">([^<]+)</gi;
  let match;
  while ((match = pattern.exec(html)) !== null) {
    const playPath = match[1];
    const cardTitle = match[2];
    const cardYear = match[3];
    const segments = playPath.split("/").filter((s, i) => i !== 0 && s);
    if (segments.length < 3) continue;
    const sourceName = decodeURIComponent(segments[1]);
    if (!sourceName) continue;
    const doubanID = (playPath.match(/douban_id=([^&]+)/) ?? [])[1] ?? "";
    results.push({
      playPath,
      sourceName,
      title: cardTitle,
      year: cardYear,
      doubanID,
    });
  }
  const q = query.toLowerCase();
  const titleMatches = results.filter((r) => r.title.toLowerCase().includes(q));
  const filtered = titleMatches.length > 0 ? titleMatches : results.filter((r) => !isDerivativeTitle(r.title));
  return filtered.sort((a, b) => {
    const aExact = a.title.toLowerCase() === q ? 1 : 0;
    const bExact = b.title.toLowerCase() === q ? 1 : 0;
    if (aExact !== bExact) return bExact - aExact;
    const aDeriv = isDerivativeTitle(a.title) ? 1 : 0;
    const bDeriv = isDerivativeTitle(b.title) ? 1 : 0;
    if (aDeriv !== bDeriv) return aDeriv - bDeriv;
    const aMapped = a.doubanID && a.doubanID !== "0" ? 1 : 0;
    const bMapped = b.doubanID && b.doubanID !== "0" ? 1 : 0;
    return bMapped - aMapped;
  });
};

/** 从播放页 HTML 提取 m3u8 直链（与 App 端 extractStreamURL 一致）。 */
const moovieExtractStreamURL = (html) => {
  const match = html.match(/initPlayer\('artplayer-app',\s*'([^']+)'/);
  if (!match) return null;
  return match[1].replace(/\\\//g, "/");
};

/** 打开播放页并提取 HLS 直链。 */
const moovieResolveStreamURL = async (playPath) => {
  const html = await moovieFetch(playPath);
  if (!html) return null;
  return moovieExtractStreamURL(html);
};

/** 从播放页 HTML 提取剧集列表（与 App 端 parseEpisodeList 一致）。 */
const moovieParseEpisodes = (html) => {
  const listMatch = html.match(/episodeList\s*=\s*\[[\s\S]*?\]/);
  if (!listMatch) return [];
  const episodes = [];
  const itemPattern = /\{\s*"title"\s*:\s*"([^"]*)",\s*"url"\s*:\s*"([^"]*)"\s*\}/g;
  let match;
  while ((match = itemPattern.exec(listMatch[0])) !== null) {
    episodes.push({ title: match[1], playPath: match[2] });
  }
  return episodes;
};

/** 拉取播放页并解析剧集列表。 */
const moovieLoadEpisodes = async (playPath) => {
  const html = await moovieFetch(playPath);
  if (!html) return [];
  return moovieParseEpisodes(html);
};

const jsonResponse = (payload, status = 200, cacheControl = "no-store") =>
  new Response(JSON.stringify(payload), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": cacheControl,
      "x-content-type-options": "nosniff",
    },
  });

/** GET /api/stream?title=&year=&original= 返回 moovie 候选源列表。
 *  中文标题搜不到时用 original（原片名）再试一次；带 year 无结果时去掉
 *  year 再试（moovie 的 year 过滤会误伤部分条目）。 */
const handleStreamAPI = async (url) => {
  const title = normalize(url.searchParams.get("title"));
  const year = normalize(url.searchParams.get("year"));
  const original = normalize(url.searchParams.get("original"));
  if (!title || title.length > 120) {
    return jsonResponse({ error: "invalid title" }, 400);
  }
  let sources = await moovieSearch(title, year);
  if (sources.length === 0 && year) {
    sources = await moovieSearch(title, "");
  }
  if (sources.length === 0 && original && original.toLowerCase() !== title.toLowerCase()) {
    sources = await moovieSearch(original, "");
  }
  return jsonResponse({ query: { title, year }, sources }, 200, "public, max-age=600");
};

/** GET /api/stream/source?path=/play/... 解析该源 m3u8（与剧集列表）。 */
const handleStreamSourceAPI = async (url) => {
  const path = normalize(url.searchParams.get("path"));
  if (!path.startsWith("/play/") || path.length > 300) {
    return jsonResponse({ error: "invalid path" }, 400);
  }
  const [streamURL, episodes] = await Promise.all([
    moovieResolveStreamURL(path),
    moovieLoadEpisodes(path),
  ]);
  if (!streamURL && episodes.length === 0) {
    return jsonResponse({ error: "unresolvable" }, 502);
  }
  return jsonResponse({ path, streamURL, episodes }, 200, "no-store");
};

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
      version: "0.8.3-test.10",
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
    originalTitle: normalize(
      isMovie ? payload.original_title : payload.original_name,
    ).slice(0, 120),
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
    .stream{margin-top:26px;border-top:1px solid #ffffff1f;padding-top:22px}
    .stream-head{display:flex;align-items:center;gap:12px;flex-wrap:wrap}
    .stream-head h2{font-size:18px;margin:0;color:#f8fafc}
    .stream-badge{padding:4px 9px;border-radius:999px;background:#f59e0b22;
    color:#fbbf24;font-size:12px;border:1px solid #f59e0b44}
    .stream-btn{padding:10px 16px;border-radius:12px;background:#f59e0b;color:#111827;
    border:0;font-weight:750;font-size:15px;cursor:pointer}
    .stream-btn:disabled{opacity:.55;cursor:wait}
    .stream-state{color:#a9b4d0;font-size:14px;margin:14px 0 0}
    .stream-error{color:#fca5a5;font-size:14px;margin:14px 0 0}
    .stream-sources{display:grid;gap:8px;margin-top:14px}
    .stream-source{display:flex;align-items:center;gap:10px;flex-wrap:wrap;padding:11px 13px;
    border:1px solid #ffffff1f;border-radius:12px;background:#ffffff0a;cursor:pointer;text-align:left}
    .stream-source:hover{border-color:#f59e0b66;background:#f59e0b0d}
    .stream-source .src-name{font-weight:700;color:#f8fafc}
    .stream-source .src-meta{color:#a9b4d0;font-size:13px}
    .stream-source .src-flag{margin-left:auto;color:#fbbf24;font-size:13px}
    .player-shell{margin-top:16px;position:relative}
    .player-shell video{width:100%;max-height:480px;border-radius:14px;background:#000}
    .episodes{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
    .ep{padding:7px 12px;border-radius:9px;border:1px solid #ffffff2e;background:#ffffff0a;
    color:#d8def0;font-size:13px;cursor:pointer}
    .ep:hover{border-color:#f59e0b88;color:#fff}
    .ep.playing{border-color:#f59e0b;background:#f59e0b22;color:#fbbf24}
    @media(max-width:650px){.card{grid-template-columns:1fr;padding:20px}.poster{max-width:280px;margin:auto}}
  </style>
</head>
<body><main><header><img class="logo" src="/cinebar-logo.svg" alt="CineBar">
<div><div class="brand">CineBar</div><div class="tagline">找到下一部好片</div></div></header>
<section class="card"><img class="poster" src="${escapeHTML(poster)}" alt="${escapeHTML(title)} 海报">
<div class="content"><h1>${escapeHTML(title)}</h1><div class="meta">
${year ? `<span class="pill">${escapeHTML(year)}</span>` : ""}
${rating ? `<span class="pill rating">★ ${escapeHTML(rating)} / 10</span>` : ""}
</div><p>${escapeHTML(summary)}</p>${castBlock}${downloadBlock}
<section class="stream" id="stream" data-title="${escapeHTML(title)}" data-year="${escapeHTML(year)}" data-original="${escapeHTML(metadata?.originalTitle ?? "")}">
  <div class="stream-head">
    <h2>在线播放</h2>
    <span class="stream-badge">实验性 · 第三方源</span>
  </div>
  <div class="stream-state" id="stream-state">加载资源源…</div>
</section>
<div class="from">由 CineBar for macOS 分享</div>
</div></section></main>
<script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.13/dist/hls.min.js"></script>
<script>
(function () {
  var host = "https://share.cinebar.cc";
  var root = document.getElementById("stream");
  if (!root) return;
  var state = document.getElementById("stream-state");
  var title = root.dataset.title || "";
  var year = root.dataset.year || "";
  var original = root.dataset.original || "";
  var candidates = [];
  var currentSource = null;
  var currentEpisodes = [];

  function esc(s) {
    return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function setState(text) { state.textContent = text; }
  function setError(text) {
    state.className = "stream-error";
    state.textContent = text;
  }
  function clearError() {
    state.className = "stream-state";
    setState("");
  }

  function loadVideo(m3u8, anchor) {
    root.querySelectorAll(".player-shell").forEach(function (el) { el.remove(); });
    var shell = document.createElement("div");
    shell.className = "player-shell";
    shell.innerHTML = '<video controls playsinline></video>';
    (anchor || root).insertAdjacentElement("afterend", shell);
    var video = shell.querySelector("video");
    if (window.Hls && Hls.isSupported()) {
      var hls = new Hls({ maxBufferLength: 30 });
      hls.loadSource(m3u8);
      hls.attachMedia(video);
      hls.on(Hls.Events.ERROR, function (_, data) {
        if (data.fatal) {
          setError("播放出错（源不可用或已失效），试试其他源。");
        }
      });
    } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = m3u8;
    } else {
      setError("当前浏览器不支持 HLS 播放。");
    }
  }

  function loadSource(path, isEpisode, anchor) {
    clearError();
    setState(isEpisode ? "正在解析该集播放地址…" : "正在解析播放地址…");
    fetch(host + "/api/stream/source?path=" + encodeURIComponent(path), { cache: "no-store" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(new Error(String(r.status))); })
      .then(function (body) {
        if (body.error) return setError("无法解析该源：" + esc(body.error));
        if (!isEpisode && body.episodes && body.episodes.length > 0) {
          currentEpisodes = body.episodes;
          renderEpisodes(anchor);
        }
        if (body.streamURL) {
          setState(isEpisode ? "正在播放该集" : "正在播放，如遇卡顿可切换源");
          loadVideo(body.streamURL, anchor);
        } else if (isEpisode) {
          setError("该集暂无可用播放地址。");
        } else {
          setState("该源没有直接播放地址，看看其他源。");
        }
      })
      .catch(function () { setError("加载失败，请稍后重试。"); });
  }

  function renderEpisodes(anchor) {
    var old = root.querySelector(".episodes");
    if (old) old.remove();
    if (!currentEpisodes.length) return;
    var wrap = document.createElement("div");
    wrap.className = "episodes";
    currentEpisodes.forEach(function (ep, i) {
      var b = document.createElement("button");
      b.className = "ep" + (i === 0 ? " playing" : "");
      b.type = "button";
      b.textContent = ep.title;
      b.addEventListener("click", function () {
        root.querySelectorAll(".ep").forEach(function (x) { x.classList.remove("playing"); });
        b.classList.add("playing");
        var target = (ep.playPath || "").indexOf("/") === 0 ? ep.playPath
          : (ep.playPath || "");
        loadSource(target, true, b);
      });
      wrap.appendChild(b);
    });
    (anchor || root).insertAdjacentElement("afterend", wrap);
  }

  function renderSources() {
    clearError();
    var old = root.querySelector(".stream-sources");
    if (old) old.remove();
    if (!candidates.length) {
      return setState("暂未找到该片的在线资源（第三方聚合源），可稍后再试或下载 CineBar 在 App 内观看。");
    }
    setState("找到 " + candidates.length + " 个源，点击选择：");
    var wrap = document.createElement("div");
    wrap.className = "stream-sources";
    candidates.forEach(function (s, i) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "stream-source";
      b.innerHTML = '<span class="src-name">' + esc(s.sourceName) + "</span>" +
        '<span class="src-meta">' + esc(s.title + (s.year ? "（" + s.year + "）" : "")) + "</span>" +
        '<span class="src-flag">' + (i === 0 ? "推荐" : "备用") + "</span>";
      b.addEventListener("click", function () {
        currentSource = s;
        loadSource(s.playPath, false, b);
      });
      wrap.appendChild(b);
    });
    root.appendChild(wrap);
  }

  function searchStreams() {
    clearError();
    setState("正在搜索在线资源源…");
    var params = new URLSearchParams({ title: title });
    if (year) params.set("year", year);
    if (original && original.toLowerCase() !== title.toLowerCase()) {
      params.set("original", original);
    }
    fetch(host + "/api/stream?" + params.toString(), { cache: "no-store" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(new Error(String(r.status))); })
      .then(function (body) {
        candidates = body.sources || [];
        renderSources();
      })
      .catch(function () { setError("在线资源加载失败，请稍后重试。"); });
  }

  searchStreams();
})();
</script></body></html>`, {
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
        version: "0.8.3-test.10",
        build: 26,
        published_at: "2026-08-03",
        download_url: "https://cinebar.cc/downloads/CineBar-0.8.3-test-build-26-universal.zip",
        notes: [
          "本地片库新增电影、电视剧和其他视频分类，自拍与屏幕录制不会自动误匹配",
          "支持手动输入片名搜索，并由用户确认影片或电视剧匹配",
          "每天最多发送一次匿名安装统计，服务端只保存 HMAC 哈希和聚合字段",
          "本地文件不上传，也不提供盗版或下载资源",
          "Build 26 已发布签名 appcast，可在 CineBar 内检查、下载并安装",
        ],
      }), {
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store",
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
    if (request.method === "GET" && url.pathname === "/api/stream/source") {
      return handleStreamSourceAPI(url);
    }
    if (request.method === "GET" && url.pathname === "/api/stream") {
      return handleStreamAPI(url);
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
