/** Cloudflare Worker entry point for the vinext-starter template. */
import { handleImageOptimization, DEFAULT_DEVICE_SIZES, DEFAULT_IMAGE_SIZES } from "vinext/server/image-optimization";
import handler from "vinext/server/app-router-entry";

interface Env {
  ASSETS: Fetcher;
  DB: D1Database;
  /** Shared with the telemetry Worker; never sent to browser code. */
  CINEBAR_TELEMETRY_ADMIN_TOKEN?: string;
  /** TMDB API key, shared with the CineBar macOS app's search, so the
   *  website search is interoperable with the in-app search. */
  TMDB_API_KEY?: string;
  IMAGES: {
    input(stream: ReadableStream): {
      transform(options: Record<string, unknown>): {
        output(options: { format: string; quality: number }): Promise<{ response(): Response }>;
      };
    };
  };
  /** 国内直播中转（CineBarRelay + Cloudflare Tunnel）：网页端被地理封锁的国内源
   *  经本机中转拉取。形如 https://xxxx.trycloudflare.com（不含结尾斜杠）。 */
  IPTV_RELAY_URL?: string;
}

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

const OFFICIAL_HOST = "cinebar.cc";
const HSTS_POLICY = "max-age=31536000; includeSubDomains";
const CONTENT_SECURITY_POLICY = "default-src 'self'; base-uri 'self'; form-action 'self' https://www.paypal.com; frame-ancestors 'none'; img-src 'self' data: blob: https://image.tmdb.org https://moovie.c2v2.com; object-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self' https://api.cinebar.cc https://share.cinebar.cc https: blob:; media-src 'self' https: blob: data:; font-src 'self' data:; upgrade-insecure-requests";
const PERMISSIONS_POLICY = "accelerometer=(), camera=(), geolocation=(), microphone=(), payment=(), usb=()";

function isAdminAnalyticsRequest(request: Request, env: Env): boolean {
  const token = env.CINEBAR_TELEMETRY_ADMIN_TOKEN;
  if (!token) return false;

  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Basic ")) return false;

  try {
    return atob(authorization.slice("Basic ".length)) === `admin:${token}`;
  } catch {
    return false;
  }
}

/** WeChat's in-app browser (WXWebView) shows an ICP warning page for
 *  offshore sites. Show a guide page instead, so visitors open the link
 *  in their system browser for a smooth reading. */
const TMDB_SEARCH_LANGUAGE: Record<string, string> = {
  "zh-Hans": "zh-CN",
  "zh-Hant": "zh-TW",
  en: "en-US",
  ja: "ja-JP",
  ko: "ko-KR",
};

/** Proxied TMDB search, sharing the same source as the macOS app's
 *  in-app search (which uses TMDB's /search/movie and /search/tv), so
 *  results are interoperable. Requires TMDB_API_KEY on the Worker. */
async function handleSearch(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const query = (url.searchParams.get("q") ?? "").trim();
  const locale = url.searchParams.get("locale") ?? "zh-Hans";
  const language = TMDB_SEARCH_LANGUAGE[locale] ?? "zh-CN";

  if (!query || query.length > 120) {
    return new Response(
      JSON.stringify({ error: "invalid query" }),
      {
        status: 400,
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
      }
    );
  }

  const key = env.TMDB_API_KEY;
  if (!key) {
    return new Response(
      JSON.stringify({ error: "search unavailable" }),
      {
        status: 503,
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
      }
    );
  }

  const base = "https://api.themoviedb.org/3";
  const common = new URLSearchParams({
    language,
    query,
    include_adult: "false",
    page: "1",
    api_key: key,
  });

  const [movieRes, tvRes] = await Promise.all([
    fetch(`${base}/search/movie?${common}`),
    fetch(`${base}/search/tv?${common}`),
  ]);

  if (!movieRes.ok && !tvRes.ok) {
    return new Response(
      JSON.stringify({
        error: "search unavailable",
        detail: `tmdb ${movieRes.status}/${tvRes.status}`,
      }),
      {
        status: 502,
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
      }
    );
  }

  const [movieData, tvData] = await Promise.all([
    movieRes.ok ? (movieRes.json() as Promise<{ results: unknown[] }>) : Promise.resolve({ results: [] }),
    tvRes.ok ? (tvRes.json() as Promise<{ results: unknown[] }>) : Promise.resolve({ results: [] }),
  ]);

  const pick = (r: Record<string, unknown>) => ({
    type: r.media_type ?? "",
    id: r.id ?? 0,
    title: r.title ?? r.name ?? "",
    year: (r.release_date ?? r.first_air_date ?? "") as string,
    poster: r.poster_path as string | null,
    rating: r.vote_average as number | null,
  });

  const results = [
    ...(movieData.results as Record<string, unknown>[]).map((r) => ({ ...pick(r), type: "movie" })),
    ...(tvData.results as Record<string, unknown>[]).map((r) => ({ ...pick(r), type: "tv" })),
  ]
    .filter((r) => r.id && r.title)
    .slice(0, 8);

  return new Response(JSON.stringify({ results }), {
    status: 200,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "public, max-age=300",
    },
  });
}

// ---------------------------------------------------------------------------
// Moovie (moovie.c2v2.com) 在线正片源解析，供官网"在线播放"。
// 与 macOS App / 分享页共用同一套搜索接口与播放页结构。
// ---------------------------------------------------------------------------
const MOOVIE_BASE = "https://moovie.c2v2.com";
const MOOVIE_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

const normalizeText = (value: string | null | undefined): string =>
  String(value ?? "").replace(/\s+/g, " ").trim();

async function moovieFetch(
  path: string,
  timeoutMs = 25000,
  retries = 2
): Promise<string | null> {
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(`${MOOVIE_BASE}${path}`, {
        headers: {
          "user-agent": MOOVIE_UA,
          accept: "text/html,application/xhtml+xml",
          "hx-request": "true",
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
}

const isDerivativeTitle = (title: string): boolean =>
  /解说|预告|花絮/.test(title);

/** 按片名+年份搜索候选源列表。 */
async function moovieSearch(
  title: string,
  year: string
): Promise<{ playPath: string; sourceName: string; doubanID: string }[]> {
  const query = normalizeText(title);
  if (!query) return [];
  const params = new URLSearchParams({ q: query });
  if (year) params.set("year", year);
  const html = await moovieFetch(`/api/htmx/search?${params}`);
  if (!html) return [];
  return moovieParseResults(html, query);
}

function moovieParseResults(
  html: string,
  query: string
): { playPath: string; sourceName: string; doubanID: string }[] {
  const results: { playPath: string; sourceName: string; doubanID: string }[] =
    [];
  const pattern =
    /href="(\/play\/[^"]+)"[^>]*class="search-result-card"[\s\S]*?card-title">([^<]+)<\/h3>[\s\S]*?card-year">([^<]+)</gi;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(html)) !== null) {
    const playPath = match[1];
    const cardTitle = match[2];
    const segments = playPath.split("/").filter((s, i) => i !== 0 && s);
    if (segments.length < 3) continue;
    const sourceName = decodeURIComponent(segments[1]);
    if (!sourceName) continue;
    const doubanID = (playPath.match(/douban_id=([^&]+)/) ?? [])[1] ?? "";
    results.push({ playPath, sourceName, title: cardTitle, year: "", doubanID });
  }
  const q = query.toLowerCase();
  const titleMatches = results.filter((r) =>
    r.title.toLowerCase().includes(q)
  );
  const filtered =
    titleMatches.length > 0
      ? titleMatches
      : results.filter((r) => !isDerivativeTitle(r.title));
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
}

/** 从播放页 HTML 提取 m3u8 直链 */
function moovieExtractStreamURL(html: string): string | null {
  const match = html.match(/initPlayer\('artplayer-app',\s*'([^']+)'/);
  if (!match) return null;
  return match[1].replace(/\\\//g, "/");
}

async function moovieResolveStreamURL(playPath: string): Promise<string | null> {
  const html = await moovieFetch(playPath);
  if (!html) return null;
  return moovieExtractStreamURL(html);
}

/** GET /api/play?title=&year= 返回该片一个可播放的 m3u8 直链。
 *  供官网搜索结果内联播放。 */
/** GET /api/play?title=&year= 返回该片一个可解析出直链的 m3u8 源。
 *  注意：分片防盗链随用户网络而异（海外探测会误判），这里只保证直链可解析，
 *  能否播由用户浏览器按其本地网络决定。 */
async function handlePlay(
  request: Request,
  env: Env
): Promise<Response> {
  const url = new URL(request.url);
  const title = normalizeText(url.searchParams.get("title"));
  const year = normalizeText(url.searchParams.get("year"));
  if (!title || title.length > 120) {
    return new Response(
      JSON.stringify({ error: "invalid title" }),
      {
        status: 400,
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
      }
    );
  }
  let sources = await moovieSearch(title, year);
  if (sources.length === 0 && year) {
    sources = await moovieSearch(title, "");
  }
  // Moovie 有结果时优先 Moovie（直链质量好、带豆瓣匹配）；
  // 否则回退到苹果CMS 源（补齐短剧/动漫/冷门片等 Moovie 覆盖不到的）。
  for (const source of sources) {
    const streamURL = await moovieResolveStreamURL(source.playPath);
    if (!streamURL) continue;
    return new Response(
      JSON.stringify({ kind: "hls", url: streamURL, label: source.sourceName }),
      {
        status: 200,
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=600" },
      }
    );
  }
  const cmsTitles = await cmsSearchAll(title);
  for (const t of cmsTitles) {
    const streamURL = cmsResolveStreamURL(t.playURL, 1);
    if (!streamURL) continue;
    return new Response(
      JSON.stringify({ kind: "hls", url: streamURL, label: `${t.sourceName} · ${t.title}` }),
      {
        status: 200,
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=600" },
      }
    );
  }
  return new Response(
    JSON.stringify({ error: "no playable source", title }),
    {
      status: 502,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
    }
  );
}

/** 从 moovie 周热度榜 HTML 解析影片卡片（标题/评分/海报代理地址）。
 *  与 App 端 parseTrendingMovies 对应。 */
function parseTrendingMovies(html: string): TrendingMovie[] {
  const items: TrendingMovie[] = [];
  const cardPattern =
    /<a href="\/search\?kw=([^"]+)&doubanId=(\d+)"[\s\S]*?<span class="movie-rating">([\d.]+)<\/span>[\s\S]*?<h3 class="movie-title" title="([^"]*)"/g;
  let match: RegExpExecArray | null;
  const seen = new Set<string>();
  while ((match = cardPattern.exec(html)) !== null) {
    const doubanID = match[2];
    if (!doubanID || seen.has(doubanID)) continue;
    seen.add(doubanID);
    const cardText = match[0];
    const posterMatch = cardText.match(/src="(\/api\/proxy\/image\/[^"]+)"/);
    if (!posterMatch) continue;
    const title = match[4];
    if (!title) continue;
    items.push({
      title,
      doubanID,
      rating: Number(match[3]) || 0,
      poster: `${MOOVIE_BASE}${posterMatch[1]}`,
    });
  }
  return items;
}

  type TrendingMovie = {
    title: string;
    doubanID: string;
    rating: number;
    poster: string;
    tmdbId?: number;
    type?: "movie" | "tv";
    tmdbPoster?: string;
  };

/** ===== 苹果CMS 资源站聚合（补充 Moovie 覆盖短板：短剧/动漫/多版本） =====
 *  与 zip0.com 背后同类的 MacCMS 资源站直接对接，无需经过 zip0。
 *  标准接口：/api.php/provide/vod/?ac=detail&wd=片名（搜索）
 *            /api.php/provide/vod/?ac=list&pg=N（全量列表，含最新更新）
 *  返回 JSON：{ code, total, list: [{ vod_id, vod_name, vod_year, vod_pic,
 *    type_name, vod_play_url, ... }] }
 *  域名已实测可用（2026-08-16）；若失效需更新 CMS_SOURCES。 */

type CMSSource = {
  id: string;       // 线路标识（对齐 zip0 的 source 字段）
  name: string;     // 线路名（"量子"/"暴风"/...）
  base: string;     // API 根地址
};

const CMS_SOURCES: CMSSource[] = [
  { id: "lzi", name: "量子", base: "https://cj.lziapi.com" },
  { id: "bfzy", name: "暴风", base: "https://bfzyapi.com" },
  { id: "zuid", name: "最大", base: "https://zuidazy.com" },
  { id: "jisu", name: "急速", base: "https://jisuzy.com" },
  { id: "ffzy", name: "非凡", base: "https://ffzy5.tv" },
];

type CMSTitle = {
  source: string;
  sourceName: string;
  id: string;            // vod_id
  title: string;         // vod_name
  year: string;
  poster: string | null;
  category: string;      // type_name（短剧/动漫/电影...）
  playURL: string;       // vod_play_url（"第01集$url#第02集$url"）
  episodeCount: number;
  remarks: string;       // vod_remarks（"TC国语v2"/"正片"等质量标签）
  playFrom: string;      // vod_play_from（线路组名，如 ffzy-m3u8）
  vodContent?: string;   // vod_content（简介，仅 detail 时带）
};

/**
 * 判定是否为衍生内容（解说/预告/花絮/混剪等）：标题或分类命中即视为衍生。
 * 与 App 端 Moovie 搜索同策略——用户要正片，解说版点击进去观感就是"放错片"。
 */
function cmsIsDerivative(title: string, category: string): boolean {
  const t = `${title ?? ""} ${category ?? ""}`;
  return /解说|预告|花絮|混剪|剪辑|片段|彩蛋|幕后|速看|抢先看|精华|合集|盘点/.test(t);
}

/** 并发搜索全部 CMS 源，返回合并结果（每源取排名最高的 1 条，总量封顶 30 条）。 */

/**
 * 标题规范化：去 [电影解说] 等括号后缀、去尾部年份（"痴迷2022"→"痴迷"）、去标点。
 * 用于同名多版本（不同年份/解说版）与搜索词的精确比对。
 */
function cmsNormalizeTitle(raw: string): string {
  return (raw || "")
    .replace(/\([^)]*\)/g, "")
    .replace(/\[[^\]]*\]/g, "")
    .replace(/\d{4}\s*$/, "")
    .replace(/[\s·:：\-—.]/g, "")
    .toLowerCase();
}

/**
 * 同名条目排序：规范化标题精确匹配 > vod_year 与请求年份一致 > 直链可播。
 * 用于"同名不同年份"场景避免拉错（如《痴迷》2022 解说 vs 2026 正片）。
 */
function cmsRankMatch(t: CMSTitle, query: string, year: string): number {
  let rank = 0;
  if (cmsNormalizeTitle(t.title) === cmsNormalizeTitle(query)) rank += 4;
  if (year && t.year === year) rank += 3;
  if (t.playURL) rank += 1;
  // 同分 tiebreaker：vod_year 最新优先（同名多版本默认选最新版，避免源站顺序把老版本排前面）。
  // 年份 4 位数 /10000 → 0.xxxx 小数权重，不影响整数档位。
  rank += (Number(t.year) || 0) / 10000;
  return rank;
}

async function cmsSearchAll(
  title: string,
  year?: string,
  signal?: AbortSignal
): Promise<CMSTitle[]> {
  const query = normalizeText(title);
  if (!query) return [];
  const results = await Promise.allSettled(
    CMS_SOURCES.map(async (src) => {
      const params = new URLSearchParams({ ac: "detail", wd: query });
      const resp = await fetch(`${src.base}/api.php/provide/vod/?${params}`, {
        headers: { "user-agent": "Mozilla/5.0", accept: "application/json" },
        signal,
      });
      if (!resp.ok) return [] as CMSTitle[];
      const data = (await resp.json()) as {
        code?: number;
        list?: Record<string, unknown>[];
      };
      if (data.code !== 1 || !Array.isArray(data.list)) return [] as CMSTitle[];
      const rows: CMSTitle[] = data.list.map((v) => {
        const playURL = String(v.vod_play_url ?? "");
        return {
          source: src.id,
          sourceName: src.name,
          id: String(v.vod_id ?? ""),
          title: String(v.vod_name ?? ""),
          year: String(v.vod_year ?? ""),
          poster: v.vod_pic ? String(v.vod_pic) : null,
          category: String(v.type_name ?? ""),
          playURL,
          episodeCount: playURL ? playURL.split("#").length : 0,
          remarks: String(v.vod_remarks ?? ""),
          playFrom: String(v.vod_play_from ?? ""),
        };
      });
      // 先过滤衍生内容（解说/预告/花絮…）
      const clean = rows.filter((r) => !cmsIsDerivative(r.title, r.category));
      if (clean.length === 0) return [] as CMSTitle[];
      // 排序后每源只留排名最高的 1 条（同名多版本合并，zip0 线路 = 每源一条）
      clean.sort((a, b) => cmsRankMatch(b, query, year ?? "") - cmsRankMatch(a, query, year ?? ""));
      return [clean[0]];
    })
  );
  const merged: CMSTitle[] = [];
  for (const r of results) {
    if (r.status === "fulfilled") merged.push(...r.value);
  }
  return merged.slice(0, 30);
}

/** 从 vod_play_url 提取指定集的 m3u8 直链（默认第 1 集）。 */
function cmsResolveStreamURL(playURL: string, episode = 1): string | null {
  if (!playURL) return null;
  const episodes = playURL.split("#").map((s) => s.trim()).filter(Boolean);
  if (episodes.length === 0) return null;
  const target = episodes[Math.min(Math.max(episode, 1), episodes.length) - 1];
  const idx = target.indexOf("$");
  if (idx < 0) return target;
  return target.slice(idx + 1).trim() || null;
}

/** 播放页解析：部分源（量子/急速/非凡）的 playURL 是播放页（非 m3u8 直链），
 *  播放页 HTML 里有相对路径的 index.m3u8（带 sign 签名），用页面域名拼出真实流。
 *  规律（2026-08 实测）：
 *    量子  var main = "/20260729/xxx/index.m3u8?sign=…"
 *    非凡  const url = "/20221114/xxx/index.m3u8?sign=…"
 *    急速  {播放页路径}/index.m3u8 直连。 */
async function resolveCMSPlayPage(pageURL: string): Promise<string | null> {
  const page = new URL(pageURL);
  // 已直连播放页的情况下，尝试 {page}/index.m3u8（急速的规律）
  const directCandidate = `${page.origin}${page.pathname.replace(/\/$/, "")}/index.m3u8`;
  try {
    const resp = await fetch(pageURL, {
      headers: { "user-agent": "Mozilla/5.0", accept: "text/html", referer: page.origin },
    });
    if (!resp.ok) return null;
    const html = await resp.text();
    // 匹配 var main = "…index.m3u8…" / const url = "…index.m3u8…"
    const m =
      html.match(/(?:var\s+main|const\s+url)\s*=\s*["']([^"']*\.m3u8[^"']*)["']/) ??
      html.match(/["']([^"']*index\.m3u8[^"']*)["']/);
    if (m && m[1]) {
      const raw = m[1].replace(/\\\//g, "/");
      try {
        return new URL(raw, page.origin).toString();
      } catch {
        return raw.startsWith("http") ? raw : null;
      }
    }
    // 回退：直接尝试 {page}/index.m3u8
    return directCandidate;
  } catch {
    return null;
  }
}

/** 解析 CineCMS 的播放地址：m3u8 直链原样返回；播放页则抓页面解析出真实 m3u8。
 *  播放页源（量子/急速/非凡）的页面由 Cloudflare 抓取不稳定，重试最多 5 次提高成功率。 */
async function resolveCMSPlayable(rawURL: string): Promise<string | null> {
  if (!rawURL) return null;
  if (/\.m3u8(\?|$)/i.test(rawURL)) return rawURL;
  for (let attempt = 0; attempt < 5; attempt++) {
    const url = await resolveCMSPlayPage(rawURL);
    if (url) return url;
    // 短暂退避后重试（Cloudflare 拉这些国内播放页抖动，稍等再试命中率更高）
    await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
  }
  return null;
}

/** GET /api/cms/search?q=&episode= 返回苹果CMS 聚合搜索结果（含直链）。 */
async function handleCMSPlay(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const q = normalizeText(url.searchParams.get("q"));
  const year = normalizeText(url.searchParams.get("year")) || undefined;
  const episode = Number(url.searchParams.get("episode")) || 1;
  if (!q || q.length > 120) {
    return new Response(
      JSON.stringify({ error: "invalid q" }),
      { status: 400, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } }
    );
  }
  const titles = await cmsSearchAll(q, year);
  const results = titles.map((t) => ({
    source: t.source,
    sourceName: t.sourceName,
    id: t.id,
    title: t.title,
    year: t.year,
    poster: t.poster,
    category: t.category,
    episodeCount: t.episodeCount,
    remarks: t.remarks,
    playFrom: t.playFrom,
    playURL: t.playURL,
    streamURL: cmsResolveStreamURL(t.playURL, episode),
  }));
  return new Response(
    JSON.stringify({ q, results }),
    {
      status: 200,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=300" },
    }
  );
}

/** 把资源站的 type_name 归类到统一大类：movie/tv/drama/anime/other。 */
function cmsClassifyCategory(raw: string): string {
  const t = raw || "";
  if (/短剧|迷你剧/.test(t)) return "drama";
  if (/动漫|动画/.test(t)) return "anime";
  if (/电影|片/.test(t)) return "movie";
  if (/剧|综艺|真人秀|纪录/.test(t)) return "tv";
  return "other";
}

/** 从单个 CMS 源拉 ac=list 某一页，归一成轻量条目（不含播放地址，展示用）。 */
async function cmsListPage(
  src: CMSSource,
  pg: number,
  signal?: AbortSignal
): Promise<{ id: string; title: string; year: string; poster: string | null; remarks: string; category: string; categoryRaw: string }[]> {
  const params = new URLSearchParams({ ac: "list", pg: String(pg) });
  try {
    const resp = await fetch(`${src.base}/api.php/provide/vod/?${params}`, {
      headers: { "user-agent": "Mozilla/5.0", accept: "application/json", referer: src.base },
      signal,
    });
    if (!resp.ok) return [];
    const data = (await resp.json()) as {
      code?: number;
      list?: Record<string, unknown>[];
    };
    if (data.code !== 1 || !Array.isArray(data.list)) return [];
    return data.list
      .map((v) => {
        const categoryRaw = String(v.type_name ?? "");
        return {
          id: String(v.vod_id ?? ""),
          title: String(v.vod_name ?? ""),
          year: String(v.vod_year ?? ""),
          poster: v.vod_pic ? String(v.vod_pic) : null,
          remarks: String(v.vod_remarks ?? ""),
          category: cmsClassifyCategory(categoryRaw),
          categoryRaw,
        };
      })
      .filter((x) => !cmsIsDerivative(x.title, x.categoryRaw));
  } catch {
    return [];
  }
}

/** 聚合指定分类的列表：从可播源拉多页，去重、过滤空标题。
 *  实测（2026-08-17 用户浏览器 hls.js）：量子、最大 ✓能播；暴风 manifestLoadError ✗不能播。
 *  故影视库只用「量子 + 最大」，排除暴风（播放走浏览器直连 m3u8）。 */
async function cmsListByCategory(
  category: string,
  pg: number
): Promise<{ items: CMSTitle[]; total: number }> {
  // 可播源：量子(lzi) + 最大(zuid)
  const stable = CMS_SOURCES.filter((s) => s.id === "lzi" || s.id === "zuid");
  if (stable.length === 0) return { items: [], total: 0 };
  const signal = AbortSignal.timeout(20000);
  const pageTasks = stable.flatMap((src) =>
    [pg, pg + 1, pg + 2].map((p) => cmsListPage(src, p, signal))
  );
  const pages = await Promise.allSettled(pageTasks);
  const merged: {
    id: string; title: string; year: string; poster: string | null; remarks: string;
    category: string; categoryRaw: string; source: string; sourceName: string;
  }[] = [];
  stable.forEach((src, i) => {
    for (let k = 0; k < 3; k++) {
      const r = pages[i * 3 + k];
      if (r.status !== "fulfilled") continue;
      for (const item of r.value) {
        if (!item.id || !item.title.trim()) continue;
        merged.push({ ...item, source: src.id, sourceName: src.name });
      }
    }
  });
  // 按 source|id 去重（不同源的同 id 是不同片，不能按裸 id 去重）
  const seen = new Map<string, typeof merged[number]>();
  for (const item of merged) {
    const key = `${item.source}|${item.id}`;
    if (!seen.has(key)) seen.set(key, item);
  }
  const uniq = Array.from(seen.values());
  // 按分类过滤
  const filtered = category === "all" ? uniq : uniq.filter((x) => x.category === category);
  let items: CMSTitle[] = filtered.map((x) => ({
    source: x.source,
    sourceName: x.sourceName,
    id: x.id,
    title: x.title,
    year: x.year,
    poster: x.poster,
    category: x.categoryRaw,
    playURL: "",
    episodeCount: 0,
    remarks: x.remarks,
    playFrom: "",
  }));
  // 补海报：ac=list 不带海报，前 12 部用 ac=detail 补（首页展示量，并行控速）。
  const posterMissing = items.slice(0, 12).filter((i) => !i.poster);
  if (posterMissing.length > 0) {
    const details = await Promise.allSettled(
      posterMissing.map(async (item) => {
        const src = CMS_SOURCES.find((s) => s.id === item.source);
        if (!src) return null;
        try {
          const params = new URLSearchParams({ ac: "detail", ids: item.id });
          const resp = await fetch(`${src.base}/api.php/provide/vod/?${params}`, {
            headers: { "user-agent": "Mozilla/5.0", accept: "application/json", referer: src.base },
            signal: AbortSignal.timeout(8000),
          });
          if (!resp.ok) return null;
          const data = (await resp.json()) as { list?: Record<string, unknown>[] };
          const pic = data.list?.[0]?.vod_pic;
          return { id: item.id, poster: pic ? String(pic) : null };
        } catch {
          return null;
        }
      })
    );
    const posterMap = new Map<string, string>();
    for (const r of details) {
      if (r.status === "fulfilled" && r.value?.poster) posterMap.set(r.value.id, r.value.poster);
    }
    items = items.map((i) => (posterMap.has(i.id) ? { ...i, poster: posterMap.get(i.id) ?? i.poster } : i));
  }
  return { items, total: items.length };
}

/** GET /api/cms/detail?id=&source= 返回单个条目的完整信息（含播放地址），供点击进详情/播放。
 *  source 指定来源（量子/暴风/…），因为不同源的 vod_id 不唯一，必须按 source 精确查，避免张冠李戴。 */
async function handleCMSDetail(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const id = normalizeText(url.searchParams.get("id"));
  const source = normalizeText(url.searchParams.get("source"));
  if (!id || id.length > 40) {
    return new Response(JSON.stringify({ error: "invalid id" }), {
      status: 400,
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
  // 指定 source 则只查该源；未指定时按 CMS_SOURCES 顺序查，取第一个有流且非空的。
  const ordered = source
    ? CMS_SOURCES.filter((s) => s.id === source)
    : CMS_SOURCES;

  const results = await Promise.allSettled(
    ordered.map(async (src) => {
      try {
        const params = new URLSearchParams({ ac: "detail", ids: id });
        const resp = await fetch(`${src.base}/api.php/provide/vod/?${params}`, {
          headers: { "user-agent": "Mozilla/5.0", accept: "application/json", referer: src.base },
          signal: AbortSignal.timeout(12000),
        });
        if (!resp.ok) return null;
        const data = (await resp.json()) as { code?: number; list?: Record<string, unknown>[] };
        if (data.code !== 1 || !Array.isArray(data.list) || !data.list.length) return null;
        const v = data.list[0];
        const playURL = String(v.vod_play_url ?? "");
        if (!playURL) return null;
        const rawFirst = cmsResolveStreamURL(playURL, 1);
        const streamURL = rawFirst ? await resolveCMSPlayable(rawFirst) : null;
        return {
          source: src.id,
          sourceName: src.name,
          id,
          title: String(v.vod_name ?? ""),
          year: String(v.vod_year ?? ""),
          poster: v.vod_pic ? String(v.vod_pic) : null,
          category: String(v.type_name ?? ""),
          playURL,
          episodeCount: playURL ? playURL.split("#").length : 0,
          remarks: String(v.vod_remarks ?? ""),
          playFrom: String(v.vod_play_from ?? ""),
          vodContent: String(v.vod_content ?? "").slice(0, 400),
          streamURL,
        };
      } catch {
        return null;
      }
    })
  );
  // 指定 source 时：直接返回该源结果（哪怕 streamURL 为 null，前端会提示）。
  if (source) {
    for (const r of results) {
      if (r.status === "fulfilled" && r.value) {
        return new Response(JSON.stringify(r.value), {
          status: 200,
          headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
        });
      }
    }
    return new Response(JSON.stringify({ error: "not found" }), {
      status: 404,
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
  // 未指定 source：优先返回 streamURL 非空的结果。
  let fallback: (typeof results)[number] | null = null;
  for (const r of results) {
    if (r.status !== "fulfilled" || !r.value) continue;
    if (r.value.streamURL) {
      return new Response(JSON.stringify(r.value), {
        status: 200,
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
      });
    }
    if (!fallback) fallback = r;
  }
  if (fallback && fallback.status === "fulfilled" && fallback.value) {
    return new Response(JSON.stringify(fallback.value), {
      status: 200,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
    });
  }
  return new Response(JSON.stringify({ error: "not found" }), {
    status: 404,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

/** GET /api/cms/list?category=&pg= 返回指定分类的聚合列表（展示用，无播放地址）。 */
async function handleCMSList(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const category = normalizeText(url.searchParams.get("category")) || "all";
  const pg = Math.max(1, Number(url.searchParams.get("pg")) || 1);
  if (!/^(all|movie|tv|drama|anime)$/.test(category)) {
    return new Response(JSON.stringify({ error: "invalid category" }), {
      status: 400,
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
  const { items, total } = await cmsListByCategory(category, pg);
  return new Response(
    JSON.stringify({ category, pg, total, items }),
    {
      status: 200,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
    }
  );
}

/** GET /api/cms/stream?url=…  解析 CineCMS 单集播放地址：m3u8 直链原样返回，播放页则抓取解析。
 *  供前端选集播放（detail 只预解析第 1 集，其余集按需解析）。 */
async function handleCMSStream(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const raw = url.searchParams.get("url");
  if (!raw || raw.length > 400) {
    return new Response(JSON.stringify({ error: "invalid url" }), {
      status: 400,
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
  const resolved = await resolveCMSPlayable(raw);
  if (!resolved) {
    return new Response(JSON.stringify({ error: "cannot resolve" }), {
      status: 502,
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
  return new Response(
    JSON.stringify({ streamURL: resolved }),
    {
      status: 200,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
    }
  );
}

/** GET /api/cms/poster?url=…  资源站海报代理：绕开防盗链/混合内容，加 CORS。
 *  豆瓣图（doubanio）防盗链要求特定 Referer，先试 movie.douban.com，失败再试无 Referer。 */
async function handleCMSPoster(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const target = url.searchParams.get("url");
  if (!target) return new Response("missing url", { status: 400 });
  const allowed = ["https://", "http://"];
  if (!allowed.some((p) => target.startsWith(p))) {
    return new Response("bad url", { status: 400 });
  }
  const ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36";
  const isDouban = /doubanio\.com/.test(target);
  // 豆瓣图先带 movie.douban.com Referer；失败再试不带 Referer。
  const attempts = isDouban
    ? [
        { "user-agent": ua, "referer": "https://movie.douban.com/" },
        { "user-agent": ua },
      ]
    : [{ "user-agent": ua, "referer": new URL(target).origin }];
  for (const headers of attempts) {
    try {
      const resp = await fetch(target, { headers: { ...headers, accept: "image/*" } });
      if (!resp.ok) continue;
      const body = await resp.arrayBuffer();
      return new Response(body, {
        status: 200,
        headers: {
          "content-type": resp.headers.get("content-type") || "image/jpeg",
          "cache-control": "public, max-age=86400",
          "access-control-allow-origin": "*",
        },
      });
    } catch { /* 换下一个尝试 */ }
  }
  return new Response("upstream failed", { status: 502 });
}


/** GET /api/trending 返回 moovie 每周热门电影与电视榜。
 *  type=all 时一次返回两榜（首页用）；type=movie 或 tv 时只返回单个榜。
 *  数据缓存在 D1，7 天有效，避免每次访问都抓取 moovie。 */
const TRENDING_CACHE_KEY = 3; // bump 以强制刷新缓存（今日热门剧改 CineCMS 兜底）
const TRENDING_CACHE_TTL_SECONDS = 24 * 60 * 60; // 每日更新（此前 7 天）

async function readTrendingCache(env: Env): Promise<{ movies: TrendingMovie[]; shows: TrendingMovie[]; fresh: boolean } | null> {
  try {
    const res = await env.DB.prepare(
      "SELECT data, updated_at FROM trending_cache WHERE id = ?"
    ).bind(TRENDING_CACHE_KEY).first<{ data: string; updated_at: number }>();
    if (!res?.data) return null;
    const now = Math.floor(Date.now() / 1000);
    const fresh = now - Number(res.updated_at) <= TRENDING_CACHE_TTL_SECONDS;
    const parsed = JSON.parse(res.data);
    return {
      movies: Array.isArray(parsed.movies) ? parsed.movies : [],
      shows: Array.isArray(parsed.shows) ? parsed.shows : [],
      fresh,
    };
  } catch {
    return null;
  }
}

async function writeTrendingCache(env: Env, movies: TrendingMovie[], shows: TrendingMovie[]): Promise<void> {
  try {
    await env.DB.prepare(
      "INSERT INTO trending_cache (id, data, updated_at) VALUES (?, ?, ?) " +
      "ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at"
    ).bind(
      TRENDING_CACHE_KEY,
      JSON.stringify({ movies, shows }),
      Math.floor(Date.now() / 1000),
    ).run();
  } catch {
    // 缓存写入失败不阻塞响应
  }
}

/** ===== IPTV 电视直播（对标 zip0 的 /tv 板块，含国际台分组） =====
 *  国内/港台源：内置列表（李钰提供并探测，151 台可用，含台标）。
 *  国际源：iptv-org（全球 187 国、14000+ 频道，按国家分组），运行时抓取并按白名单过滤知名国际台，
 *          URL 随源站每日更新，不会过期失效。
 *  GET /api/iptv 返回按分组组织的频道列表（央视/卫视/港台/地方 + 各国国际台）。 */

/**
 * 内置直播源（2026-08-18 李钰提供，已批量探测剔除不可用，151 台可用）。
 * 含台标 tvg-logo（epg.112114.xyz）；分组：央视频道 / 卫视频道 / 港台频道 / 地方频道。
 * 替换原 best-fan/iptv-sources 国内源；国际台（iptv-org）逻辑保留不变。
 */
const IPTV_BUILTIN_M3U = `#EXTM3U
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV1%E7%BB%BC%E5%90%88.png" group-title="央视频道",CCTV1综合
http://119.233.255.62:1234/608807420
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV2%E8%B4%A2%E7%BB%8F.png" group-title="央视频道",CCTV2财经
http://119.233.255.62:1234/631780532
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV3%E7%BB%BC%E8%89%BA.png" group-title="央视频道",CCTV3综艺
http://119.233.255.62:1234/624878271
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV4%E4%B8%AD%E6%96%87%E5%9B%BD%E9%99%85.png" group-title="央视频道",CCTV4中文国际
http://119.233.255.62:1234/631780421
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV4%E6%AC%A7%E6%B4%B2.png" group-title="央视频道",CCTV4欧洲
http://119.233.255.62:1234/608807419
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV4%E7%BE%8E%E6%B4%B2.png" group-title="央视频道",CCTV4美洲
http://119.233.255.62:1234/608807416
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV5%E4%BD%93%E8%82%B2.png" group-title="央视频道",CCTV5体育
http://119.233.255.62:1234/641886683
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV5%2B%E4%BD%93%E8%82%B2%E8%B5%9B%E4%BA%8B.png" group-title="央视频道",CCTV5+体育赛事
http://119.233.255.62:1234/641886773
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV6%E7%94%B5%E5%BD%B1.png" group-title="央视频道",CCTV6电影
http://119.233.255.62:1234/624878396
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV7%E5%9B%BD%E9%98%B2%E5%86%9B%E4%BA%8B.png" group-title="央视频道",CCTV7国防军事
http://119.233.255.62:1234/673168121
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV8%E7%94%B5%E8%A7%86%E5%89%A7.png" group-title="央视频道",CCTV8电视剧
http://119.233.255.62:1234/624878356
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV9%E7%BA%AA%E5%BD%95.png" group-title="央视频道",CCTV9纪录
http://119.233.255.62:1234/673168140
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV10%E7%A7%91%E6%95%99.png" group-title="央视频道",CCTV10科教
http://119.233.255.62:1234/624878405
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV11%E6%88%8F%E6%9B%B2.png" group-title="央视频道",CCTV11戏曲
http://119.233.255.62:1234/667987558
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV12%E7%A4%BE%E4%BC%9A%E4%B8%8E%E6%B3%95.png" group-title="央视频道",CCTV12社会与法
http://119.233.255.62:1234/673168185
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV13%E6%96%B0%E9%97%BB.png" group-title="央视频道",CCTV13新闻
http://119.233.255.62:1234/608807423
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV14%E5%B0%91%E5%84%BF.png" group-title="央视频道",CCTV14少儿
http://119.233.255.62:1234/624878440
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV15%E9%9F%B3%E4%B9%90.png" group-title="央视频道",CCTV15音乐
http://119.233.255.62:1234/673168223
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CCTV17%E5%86%9C%E4%B8%9A%E5%86%9C%E6%9D%91.png" group-title="央视频道",CCTV17农业农村
http://119.233.255.62:1234/673168256
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CGTN%E8%8B%B1%E8%AF%AD.png" group-title="央视频道",CGTN英语
https://english-livebkali.cgtn.com/live/encgtn_0.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CGTN%E7%BA%AA%E5%BD%95.png" group-title="央视频道",CGTN纪录
http://english-livebkali.cgtn.com/live/doccgtn_0.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E4%B8%9C%E6%96%B9%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",东方卫视
http://119.233.255.62:1234/651632648
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B1%9F%E8%8B%8F%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",江苏卫视
http://119.233.255.62:1234/623899368
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%B9%BF%E4%B8%9C%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",广东卫视
http://119.233.255.62:1234/608831231
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%8C%97%E4%BA%AC%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",北京卫视
http://119.233.255.62:1234/630287636
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E8%BE%BD%E5%AE%81%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",辽宁卫视
http://119.233.255.62:1234/630291707
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B2%B3%E5%8C%97%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",河北卫视
http://119.233.255.62:1234/962042070
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B1%9F%E8%A5%BF%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",江西卫视
http://119.233.255.62:1234/783847495
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B2%B3%E5%8D%97%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",河南卫视
http://119.233.255.62:1234/790187291
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%99%95%E8%A5%BF%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",陕西卫视
http://119.233.255.62:1234/738910838
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%A4%A7%E6%B9%BE%E5%8C%BA%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",大湾区卫视
http://119.233.255.62:1234/608917627
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B9%96%E5%8C%97%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",湖北卫视
http://119.233.255.62:1234/947472496
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B5%B7%E5%B3%A1%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",海峡卫视
http://119.233.255.62:1234/849119120
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E4%B8%AD%E5%9B%BD%E5%86%9C%E6%9E%97%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",农林卫视
http://119.233.255.62:1234/956904896
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%85%B5%E5%9B%A2%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",兵团卫视
http://119.233.255.62:1234/956923145
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%BB%91%E9%BE%99%E6%B1%9F%E5%8D%AB%E8%A7%86.png" group-title="卫视频道",黑龙江卫视
http://119.233.255.62:1234/738906901
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%87%A4%E5%87%B0%E4%B8%AD%E6%96%87.png" group-title="港台频道",凤凰中文
http://zmgd.zyrnet.com:8888/hls/110/index.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%87%A4%E5%87%B0%E8%B5%84%E8%AE%AF.png" group-title="港台频道",凤凰资讯
http://zmgd.zyrnet.com:8888/hls/109/index.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%87%A4%E5%87%B0%E9%A6%99%E6%B8%AF.png" group-title="港台频道",凤凰香港
https://cdn.qd.je/163189/fhhk
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E4%B8%AD%E8%A6%96%E6%96%B0%E8%81%9E.png" group-title="港台频道",中視新聞
http://4gtv.cnlive.club/channel/7e6461d6/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E4%B8%AD%E5%A4%A9%E6%96%B0%E8%81%9E%E5%8F%B0.png" group-title="港台频道",中天新聞
http://4gtv.cnlive.club/channel/3824d067/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/TVB%E6%96%B0%E9%97%BB.png" group-title="港台频道",TVB新闻
https://cdn6.cc.cd/163189/wxxw
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/TVB%E6%98%9F%E6%B2%B3.png" group-title="港台频道",TVB星河
https://cdn6.cc.cd/163189/tvbxh
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%98%8E%E7%8F%A0%E5%8F%B0(%E5%AD%97%E5%B9%95).png" group-title="港台频道",明珠台
https://cdn.qd.je/163189/mzt
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E7%BF%A1%E7%BF%A0%E5%8F%B0%E5%AD%97%E5%B9%95.png" group-title="港台频道",翡翠台
https://cdn3.indevs.in/stream/tvb/fct/
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/TVB%E4%BA%9A%E6%B4%B2%E6%AD%A6%E4%BE%A0.png" group-title="港台频道",TVB亚洲武侠
https://cdn6.cc.cd/163189/yzwx
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/TVB%E5%A8%B1%E4%B9%90%E6%96%B0%E9%97%BB%E5%8F%B0.png" group-title="港台频道",TVB娱乐新闻台
https://cdn6.cc.cd/163189/ylxw
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/TVB1.png" group-title="港台频道",TVB1
https://cdn6.cc.cd/163189/tvb1
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/TVBJ1.png" group-title="港台频道",TVBJ1
https://cdn6.cc.cd/163189/j1
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%97%A0%E7%BA%BF%E6%96%B0%E9%97%BB%E5%8F%B0.png" group-title="港台频道",无线新闻台
https://cdn6.cc.cd/163189/wxxwt
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/TVBPlus.png" group-title="港台频道",TVBPlus
https://cdn3.indevs.in/stream/tvb/tvbp/
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/HOY%20TV.png" group-title="港台频道",HOY TV
https://cdn.qd.je/163189/hoy
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/HOY%E8%B5%84%E8%AE%AF%E5%8F%B0.png" group-title="港台频道",HOY资讯台
https://cdn.qd.je/163189/hoy78
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/HOY%E5%9B%BD%E9%99%85%E8%B4%A2%E7%BB%8F%E5%8F%B0.png" group-title="港台频道",HOY国际财经台
https://cdn.qd.je/163189/hoy76
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/ViuTV.png" group-title="港台频道",ViuTV
https://cdn.qd.je/163189/viu
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/ViuTVsix.png" group-title="港台频道",ViuTVsix
https://cdn.qd.je/163189/viu6
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/NOW%E6%96%B0%E9%97%BB%E5%8F%B0.png" group-title="港台频道",NOW新闻台
https://cdn.qd.je/163189/now
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/RTHK31.png" group-title="港台频道",RTHK31
https://cdn.qd.je/163189/rthk31
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/RTHK32.png" group-title="港台频道",RTHK32
https://cdn.qd.je/163189/rthk32
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%BE%B3%E8%A7%86%E6%BE%B3%E9%97%A8.png" group-title="港台频道",澳视澳门
https://cdn.qd.je/163189/asam
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%BE%B3%E8%A7%86%E5%8D%AB%E6%98%9F.png" group-title="港台频道",澳视卫星
https://cdn.qd.je/163189/as
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%BE%B3%E9%97%A8%E4%BD%93%E8%82%B2.png" group-title="港台频道",澳门体育
https://cdn.qd.je/163189/amty
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%BE%B3%E9%97%A8%E7%BB%BC%E8%89%BA.png" group-title="港台频道",澳门综艺
https://cdn.qd.je/163189/amzy
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%BE%B3%E9%97%A8%E8%8E%B2%E8%8A%B1.png" group-title="港台频道",澳门莲花
https://cdn.qd.je/163189/amlh
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%87%8D%E6%B8%A9%E7%BB%8F%E5%85%B8.png" group-title="港台频道",重温经典
https://cdn.qd.je/163189/cwjd
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CH5.png" group-title="港台频道",CH5
https://cdn.qd.je/163189/ch5
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CH8.png" group-title="港台频道",CH8
https://cdn.qd.je/163189/ch8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/CHU.png" group-title="港台频道",CHU
https://cdn.qd.je/163189/chu
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%BE%99%E5%8D%8E%E7%94%B5%E5%BD%B1.png" group-title="港台频道",龙华电影
https://cdn.qd.je/163189/lhdy
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%BE%99%E5%8D%8E%E7%BB%8F%E5%85%B8.png" group-title="港台频道",龙华经典
https://cdn.qd.je/163189/lhjd
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%BE%99%E5%8D%8E%E5%81%B6%E5%83%8F.png" group-title="港台频道",龙华偶像
https://cdn.qd.je/163189/lhox
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%BE%99%E5%8D%8E%E6%97%A5%E9%9F%A9.png" group-title="港台频道",龙华日韩
https://cdn.qd.je/163189/lhrh
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%BE%99%E5%8D%8E%E6%88%8F%E5%89%A7.png" group-title="港台频道",龙华戏剧
https://cdn.qd.je/163189/lhxj
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%BE%99%E5%8D%8E%E6%B4%8B%E7%89%87.png" group-title="港台频道",龙华洋片
https://cdn.qd.je/163189/lhyp
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%BE%99%E5%8D%8E%E5%8D%A1%E9%80%9A.png" group-title="港台频道",龙华卡通
https://cdn.qd.je/163189/lhkt
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%A4%A9%E6%98%A0%E6%96%B0%E5%8A%A0%E5%9D%A1.png" group-title="港台频道",天映频道
https://cdn.qd.je/163189/typd
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B0%91%E8%A6%96%E7%AC%AC%E4%B8%80%E5%8F%B0.png" group-title="港台频道",民視第一台
http://4gtv.cnlive.club/channel/nc56ba28/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B0%91%E8%A6%96%E5%8F%B0%E7%81%A3%E5%8F%B0.png" group-title="港台频道",民視台灣台
http://4gtv.cnlive.club/channel/nce5d867/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B0%91%E8%A6%96.png" group-title="港台频道",民視
http://4gtv.cnlive.club/channel/n7222a63c/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E8%8F%AF%E8%A6%96.png" group-title="港台频道",華視
http://4gtv.cnlive.club/channel/n721fc25a/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E4%B8%89%E7%AB%8B%E7%B6%9C%E5%90%88%E5%8F%B0.png" group-title="港台频道",三立綜合台
http://4gtv.cnlive.club/channel/45c7d3e3/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/TVBS%E7%B2%BE%E9%87%87%E5%8F%B0.png" group-title="港台频道",TVBS精采台
http://4gtv.cnlive.club/channel/49d50255/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%9D%96%E5%A4%A9%E7%B6%9C%E5%90%88%E5%8F%B0.png" group-title="港台频道",靖天綜合台
http://4gtv.cnlive.club/channel/3f6ecb92/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%9D%96%E5%A4%A9%E6%97%A5%E6%9C%AC%E5%8F%B0.png" group-title="港台频道",靖天日本台
http://4gtv.cnlive.club/channel/3f1816f7/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/LiveABC%E4%BA%92%E5%8B%95%E8%8B%B1%E8%AA%9E%E9%A0%BB%E9%81%93.png" group-title="港台频道",ABC互動英語
http://4gtv.cnlive.club/channel/2a571abf/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%9D%96%E5%A4%A9%E5%8D%A1%E9%80%9A%E5%8F%B0.png" group-title="港台频道",靖天卡通台
http://4gtv.cnlive.club/channel/3ed78a45/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%9D%96%E6%B4%8B%E5%8D%A1%E9%80%9ANice%20Bingo.png" group-title="港台频道",Nice Bingo
http://4gtv.cnlive.club/channel/n15c65427/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/MOMO%E8%A6%AA%E5%AD%90%E5%8F%B0.png" group-title="港台频道",MOMO親子台
http://4gtv.cnlive.club/channel/n33a56e39/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%8F%A1%E9%9B%BB%E8%A6%96%E6%96%B0%E8%81%9E%E5%8F%B0.png" group-title="港台频道",Mnews鏡新闻
http://4gtv.cnlive.club/channel/351c8485/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%9D%B1%E6%A3%AE%E6%96%B0%E8%81%9E%E5%8F%B0.png" group-title="港台频道",東森新聞
http://4gtv.cnlive.club/channel/n5ca63a3a/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E8%8F%AF%E8%A6%96%E6%96%B0%E8%81%9E.png" group-title="港台频道",華視新聞
http://4gtv.cnlive.club/channel/n692bc32c/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B0%91%E8%A6%96%E6%96%B0%E8%81%9E%E5%8F%B0.png" group-title="港台频道",民視新聞台
http://4gtv.cnlive.club/channel/nca14742/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E4%B8%89%E7%AB%8B%E6%96%B0%E8%81%9EiNEWS.png" group-title="港台频道",三立新聞iNEWS
http://4gtv.cnlive.club/channel/4fa717ad/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/TVBS%E6%96%B0%E8%81%9E.png" group-title="港台频道",TVBS新聞
http://4gtv.cnlive.club/channel/n1ea96b20/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%9D%B1%E6%A3%AE%E8%B2%A1%E7%B6%93%E6%96%B0%E8%81%9E%E5%8F%B0.png" group-title="港台频道",東森財經新聞台
http://4gtv.cnlive.club/channel/57ce2e74/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%AF%B0%E5%AE%87%E6%96%B0%E8%81%9E%E5%8F%B0.png" group-title="港台频道",寰宇新聞台
http://4gtv.cnlive.club/channel/n4da4274/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%AF%B0%E5%AE%87%E6%96%B0%E8%81%9E%E5%8F%B0%E7%81%A3%E5%8F%B0.png" group-title="港台频道",寰宇新聞台灣台
http://4gtv.cnlive.club/channel/n37458587/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/TVBS.png" group-title="港台频道",TVBS
http://4gtv.cnlive.club/channel/58f128b2/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B0%91%E8%A6%96%E7%B6%9C%E8%97%9D%E5%8F%B0.png" group-title="港台频道",民視綜藝台
http://4gtv.cnlive.club/channel/nc46cff5/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%9D%96%E5%A4%A9%E8%82%B2%E6%A8%82%E5%8F%B0.png" group-title="港台频道",靖天育樂台
http://4gtv.cnlive.club/channel/3f7d0a6e/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/KLT-%E9%9D%96%E5%A4%A9%E5%9C%8B%E9%99%85%E5%8F%B0.png" group-title="港台频道",靖天國際台
http://4gtv.cnlive.club/channel/n481b36ac/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/Nice%20TV%20%E9%9D%96%E5%A4%A9%E6%AD%A1%E6%A8%82%E5%8F%B0.png" group-title="港台频道",靖天歡樂台
http://4gtv.cnlive.club/channel/n122ce57e/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%9D%96%E5%A4%A9%E8%B3%87%E8%A8%8A%E5%8F%B0.png" group-title="港台频道",靖天資訊台
http://4gtv.cnlive.club/channel/3fae463b/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/TVBS%E6%AD%A1%E6%A8%82%E5%8F%B0.png" group-title="港台频道",TVBS歡樂台
http://4gtv.cnlive.club/channel/498f035d/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%85%AC%E8%A6%96%E6%88%B2%E5%89%A7.png" group-title="港台频道",公視戲劇
http://4gtv.cnlive.club/channel/7fdd881e/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%9D%96%E5%A4%A9%E6%88%8F%E5%89%A7%E5%8F%B0.png" group-title="港台频道",靖天戲劇台
http://4gtv.cnlive.club/channel/3f07b409/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%9D%96%E6%B4%8B%E6%88%8F%E5%89%A7%E5%8F%B0.png" group-title="港台频道",靖洋戲劇台
http://4gtv.cnlive.club/channel/48117ce7/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%9D%96%E5%A4%A9%E6%98%A0%E7%95%AB.png" group-title="港台频道",靖天映畫
http://4gtv.cnlive.club/channel/n610faa83/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%9D%96%E5%A4%A9%E9%9B%BB%E5%BD%B1%E5%8F%B0.png" group-title="港台频道",靖天電影台
http://4gtv.cnlive.club/channel/3fcf6ae8/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/amc%E9%9B%BB%E5%BD%B1%E5%8F%B0.png" group-title="港台频道",amc電影台
http://4gtv.cnlive.club/channel/n4f2af9e/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E7%B6%93%E5%85%B8%E9%9B%BB%E5%BD%B1%E5%8F%B0.png" group-title="港台频道",經典電影台
http://4gtv.cnlive.club/channel/n2eb7240a/index.m3u8?q=1784702901150
#EXTINF:-1 tvg-name="公视" tvg-logo="https://epg.112114.xyz/logo/公视.png" group-title="港台频道",公视高清
http://211.72.174.95:8116/0.ts
#EXTINF:-1 tvg-name="民视" tvg-logo="https://epg.112114.xyz/logo/民视.png" group-title="港台频道",民视高清
http://211.72.174.95:8115/0.ts
#EXTINF:-1 tvg-name="华视" tvg-logo="https://epg.112114.xyz/logo/华视.png" group-title="港台频道",华视高清
http://220.135.241.47:8317/0.ts
#EXTINF:-1 tvg-name="台视" tvg-logo="https://epg.112114.xyz/logo/台视.png" group-title="港台频道",台视高清
http://211.72.174.95:8112/0.ts
#EXTINF:-1 tvg-name="华视" tvg-logo="https://epg.112114.xyz/logo/华视.png" group-title="港台频道",华视教体
http://220.135.241.47:8318/0.ts
#EXTINF:-1 tvg-name="台视财经" tvg-logo="https://epg.112114.xyz/logo/台视财经.png" group-title="港台频道",台视财经
http://220.135.241.47:8315/0.ts
#EXTINF:-1 tvg-name="Taiwan+" tvg-logo="https://epg.112114.xyz/logo/Taiwan+.png" group-title="港台频道",Taiwan+
https://fastly.live.brightcove.com/6385235869112/ap-northeast-1/6282251407001/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJob3N0IjoiaWU4OWZvLmVncmVzcy5pdjNqZDgiLCJhY2NvdW50X2lkIjoiNjI4MjI1MTQwNzAwMSIsImVobiI6ImZhc3RseS5saXZlLmJyaWdodGNvdmUuY29tIiwiaXNzIjoiYmxpdmUtcGxheWJhY2stc291cmNlLWFwaSIsInN1YiI6InBhdGhtYXB0b2tlbiIsImF1ZCI6WyI2MjgyMjUxNDA3MDAxIl0sImp0aSI6IjYzODUyMzU4NjkxMTIifQ.4c-V1Ks3nBx9nRljtn5-jCNP_nLuWBbk-pw9BFWZfMQ/playlist-hls.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B2%B3%E5%8C%974K.png" group-title="地方频道",河北4K
https://event.pull.hebtv.com:443/live/live101.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E7%9C%8B%E4%B8%9C%E6%96%B94K.png" group-title="地方频道",看东方4K
http://bp-resource-dfl.bestv.cn/148/3/video.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E8%8B%8F%E5%B7%9E4K.png" group-title="地方频道",苏州4K
https://live-auth.51kandianshi.com/szgd/csztv4k_4k.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%92%B1%E6%B1%9F%E9%83%BD%E5%B8%82.png" group-title="地方频道",钱江都市
http://ali-xwl.cztv.com/live/channel021080Plxw.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E7%BB%8F%E6%B5%8E%E7%94%9F%E6%B4%BB.png" group-title="地方频道",经济生活
http://ali-xwl.cztv.com/live/channel031080Plxw.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%95%99%E7%A7%91%E5%BD%B1%E9%99%A2.png" group-title="地方频道",教科影院
http://ali-xwl.cztv.com/live/channel041080Plxw.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B0%91%E7%94%9F%E4%BC%91%E9%97%B2.png" group-title="地方频道",民生休闲
http://ali-xwl.cztv.com/live/channel061080Plxw.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B5%99%E6%B1%9F%E6%96%B0%E9%97%BB.png" group-title="地方频道",浙江新闻
http://ali-xwl.cztv.com/live/channel071080Plxw.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%B0%91%E5%84%BF%E9%A2%91%E9%81%93.png" group-title="地方频道",少儿频道
http://ali-xwl.cztv.com/live/channel081080Plxw.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B5%99%E6%B1%9F%E5%9B%BD%E9%99%85.png" group-title="地方频道",浙江国际
http://ali-xwl.cztv.com/live/channel101080Plxw.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E4%B9%8B%E6%B1%9F%E7%BA%AA%E5%BD%95.png" group-title="地方频道",之江纪录
http://ali-xwl.cztv.com/live/channel121080Pnew.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%B9%BF%E5%B7%9E%E7%BB%BC%E5%90%88.png" group-title="地方频道",广州综合
https://tencentplaygsm.gztv.com/live/zonghes.m3u8?txTime=65797c44&txSecret=7e4590b2320037d7ce49ce9eac2dd6c0
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%8D%97%E5%9B%BD%E9%83%BD%E5%B8%82.png" group-title="地方频道",南国都市
https://tencentplay.gztv.com/live/nanguodushi.m3u8?txSecret=550af55c0ea34ce492748481415b6dfa&txTime=1903e7b17de
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E8%8B%8F%E5%B7%9E%E5%A8%B1%E4%B9%90.png" group-title="地方频道",苏州娱乐
https://live-auth.51kandianshi.com/szgd/csztv4.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%8D%97%E5%AE%81%E6%96%B0%E9%97%BB.png" group-title="地方频道",南宁新闻
https://hls.nntv.cn/nnlive/XWZH_24.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%8D%97%E5%AE%81%E6%96%87%E6%97%85.png" group-title="地方频道",南宁文旅
https://hls.nntv.cn/nnlive/WLSH_24.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E5%8D%97%E5%AE%81%E5%A8%B1%E4%B9%90.png" group-title="地方频道",南宁娱乐
http://hls.nntv.cn/nnlive/YSYL_244.m3u8
#EXTINF:-1 tvg-id="内蒙古新闻综合" tvg-logo="https://epg.112114.xyz/logo/%E6%96%B0%E9%97%BB%E7%BB%BC%E5%90%88.png" group-title="地方频道",新闻综合
http://play1-qk.nmtv.cn/live/2316general.m3u8
#EXTINF:-1 tvg-id="内蒙古经济生活" tvg-logo="https://epg.112114.xyz/logo/%E5%86%85%E8%92%99%E5%8F%A4%E7%BB%8F%E6%B5%8E%E7%94%9F%E6%B4%BB%E9%A2%91%E9%81%93.png" group-title="地方频道",内蒙古经济生活频道
http://play1-qk.nmtv.cn/live/2326general.m3u8
#EXTINF:-1 tvg-id="内蒙古少儿" tvg-logo="https://epg.112114.xyz/logo/%E5%86%85%E8%92%99%E5%8F%A4%E5%B0%91%E5%84%BF%E9%A2%91%E9%81%93.png" group-title="地方频道",内蒙古少儿频道
http://play1-qk.nmtv.cn/live/2327general.m3u8
#EXTINF:-1 tvg-id="内蒙古文体娱乐" tvg-logo="https://epg.112114.xyz/logo/%E6%96%87%E4%BD%93%E5%A8%B1%E4%B9%90.png" group-title="地方频道",文体娱乐
http://play1-qk.nmtv.cn/live/2319general.m3u8
#EXTINF:-1 tvg-id="内蒙古农牧" tvg-logo="https://epg.112114.xyz/logo/%E5%86%9C%E7%89%A7%E9%A2%91%E9%81%93.png" group-title="地方频道",农牧频道
http://play1-qk.nmtv.cn/live/2329general.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%A2%A8%E5%9B%AD%E9%A2%91%E9%81%93.png" group-title="地方频道",梨园频道
https://dxtx.hntv.tv/live/lypd.m3u8?txSecret=10c771842a0be59e8b575d765173ec96&txTime=7B923E0A&wsSecret=1966aa8a0405e1541cff782f56c75447&wsTime=1770400669
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%96%87%E7%89%A9%E5%AE%9D%E5%BA%93.png" group-title="地方频道",文物宝库
https://dxtx.hntv.tv/live/wwbk.m3u8?txSecret=317b89626134fd6bea6e129455b5ff18&txTime=7C4C635C&wsSecret=87c5daf4f4c3a09fb4e4cce0843d4a1c&wsTime=1770400669
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%AD%A6%E6%9C%AF%E9%A2%91%E9%81%93.png" group-title="地方频道",武术频道
https://dxtx.hntv.tv/live/wssj.m3u8?txSecret=c38b4d31ba4c45c6babb5c47132123e3&txTime=7ABB976A&wsSecret=dfcdc24ac8a49ebd886337dc5cdc1568&wsTime=1770400669
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%B2%B3%E5%8D%97%E6%9B%B2%E8%89%BA.png" group-title="地方频道",河南曲艺
https://dxtx.hntv.tv/live/jczy.m3u8?txSecret=e785008e49564e5e738439b4dd2ae68e&txTime=7C4C6207&wsSecret=3f9e1d6e5c78cea99a876ce40f13202b&wsTime=1770400669
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E7%BB%8D%E5%85%B4%E5%85%AC%E5%85%B1.png" group-title="地方频道",绍兴公共
http://live.shaoxing.com.cn/video/s10001-sxtv2/index.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%96%87%E5%8C%96%E5%BD%B1%E8%A7%86.png" group-title="地方频道",文化影视
http://live.shaoxing.com.cn/video/s10001-sxtv3/index.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E6%96%87%E6%88%90%E7%BB%BC%E5%90%88.png" group-title="地方频道",文成综合
http://l.cztvcloud.com/channels/lantian/SXwencheng1/720p.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E8%90%A7%E5%B1%B1%E7%BB%BC%E5%90%88.png" group-title="地方频道",萧山综合
http://l.cztvcloud.com/channels/lantian/SXxiaoshan1/720p.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E9%BE%99%E6%B3%89%E7%BB%BC%E5%90%88.png" group-title="地方频道",龙泉综合
http://l.cztvcloud.com/channels/lantian/SXlongquan1/720p.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E4%B8%8A%E8%99%9E%E7%BB%BC%E5%90%88.png" group-title="地方频道",上虞综合
http://l.cztvcloud.com/channels/lantian/SXshangyu1/720p.m3u8
#EXTINF:-1 tvg-logo="https://epg.112114.xyz/logo/%E4%BA%91%E5%92%8C%E7%BB%BC%E5%90%88.png" group-title="地方频道",云和综合
http://l.cztvcloud.com/channels/lantian/SXyunhe1/720p.m3u8`;


const IPTV_INTL_SOURCES = [
  { id: "intl", name: "国际", url: "https://iptv-org.github.io/iptv/index.country.m3u" },
];

type IPTVChannel = {
  name: string;
  logo: string | null;
  url: string;
  group: string;
  responseTime: string;
  /** 从 Cloudflare 网络能否访问（网页端据此只展示可播台；App 直连国内不受限）。 */
  reachable?: boolean;
  /** 网页端不可播（源站 Cloudflare 网络不可达或裸流浏览器不支持），App 直连不受影响。 */
  webUnplayable?: boolean;
};

const IPTV_CACHE_KEY = 22; // 网页（2026-08-18 二次升 key：旧 key 20 缓存含 Cloudflare 误判的 reachable=false，且部署 token 无 D1 权限无法清理）；2~18、20 已弃用
const IPTV_CACHE_KEY_APP = 23; // App（2026-08-18 二次升 key）
// best-fan 源每日自动重建，12 小时抓取一次即可跟上换源节奏；
// 抓取失败时回退旧缓存（见 handleIPTV），避免源站抖动导致列表清空。
const IPTV_CACHE_TTL_SECONDS = 12 * 60 * 60;

// 国际台白名单（纯子串 + 少量  正则），过滤 iptv-org 的知名国际台
const INTL_PLAIN: Record<string, string[]> = {
  'United States': ['fox news', 'msnbc', 'cnbc', 'bloomberg', 'abc news', 'cbs news', 'nbc news', 'pbs', 'c-span', 'newsmax', 'the weather channel', 'newsnation', 'cheddar', 'usa today'],
  'United Kingdom': ['bbc news', 'sky news', 'itv', 'channel 4', 'bbc one', 'bbc two', 'gb news'],
  'Japan': ['nhk world', 'nhk general', 'nhk news', 'tokyo mx', 'tbs news', 'fuji', 'tv asahi', 'ntv'],
  'South Korea': ['arirang', 'kbs world', 'ytn', 'mbc', 'sbs news', 'jtbc', 'tv chosun', 'channel a', 'kbs news'],
  'Hong Kong': ['tvb', 'now news', 'hoy', 'viutv', 'rthk', 'i-cable'],
  'Taiwan': ['tvbs', 'cts', 'ttv', 'ctv', 'set', 'ftv', 'next tv', 'ebc', 'da ai', 'formosa', 'hakka'],
  'France': ['france 24', 'bfm', 'tf1', 'france 2', 'france 3', 'm6', 'arte', 'lci', 'cnews', 'france info'],
  'Germany': ['dw english', 'dw deutsch', 'wdr', 'ndr', 'br fernsehen', 'n-tv', 'rtl', 'prosieben', 'arte', 'phoenix'],
  'Australia': ['abc news', 'abc australia', 'sbs', 'channel 9', 'channel 7', 'channel 10', '7 news', '9 news', 'sky news australia'],
  'Canada': ['cbc news', 'ctv news', 'global news', 'cp24', 'citynews', 'bnn bloomberg'],
  'Russia': ['rt international', 'rt news', 'russia today', 'rt documentary'],
  'India': ['ndtv 24x7', 'times now', 'cnn-news18', 'republic', 'wion', 'india today', 'aaj tak', 'dd news'],
  'Singapore': ['channel newsasia', 'cna', 'mediacorp', 'channel 5', 'channel 8'],
  'Qatar': ['al jazeera english', 'al jazeera arabic', 'al jazeera'],
  'Turkey': ['trt world', 'trt 1', 'trt haber', 'cnn turk', 'haberturk'],
  'Switzerland': ['srf', 'rts'],
  'Netherlands': ['nos', 'bnr', 'npo'],
  'Italy': ['rai', 'sky tg24', 'tgcom', 'canale 5', 'rete 4', 'italia 1'],
  'Spain': ['rtve', 'la 1', 'antena 3', 'telecinco', 'la sexta', 'cuatro', '24h'],
  'Mexico': ['televisa', 'azteca', 'imagen'],
  'Argentina': ['telefe', 'el trece', 'c5n', 'a24', 'cronica'],
  'Brazil': ['globo', 'record', 'band', 'sbt', 'cnn brasil', 'jovem pan'],
  'Thailand': ['thai pbs', 'channel 3', 'mcot', 'nbt'],
  'Vietnam': ['vtv1', 'vtv4', 'htv', 'vtc'],
  'Philippines': ['abs-cbn', 'gma', 'cnn philippines', 'anc'],
  'Indonesia': ['kompas tv', 'metro tv', 'tvri', 'cnn indonesia', 'rcti'],
  'Malaysia': ['rtm', 'astro', 'tv3'],
  'Saudi Arabia': ['al arabiya', 'al ekhbariya', 'saudi', 'mbc'],
  'Israel': ['i24news', 'kan', 'channel 13', 'channel 12'],
  'Ukraine': ['ukraine 24', 'inter', '1+1', 'ictv'],
  'Poland': ['tvn24', 'polsat', 'tvp'],
  'Norway': ['nrk', 'tv2'],
  'Sweden': ['svt', 'tv4'],
  'Denmark': ['dr1', 'tv2'],
  'Austria': ['orf'],
  'Belgium': ['rtbf', 'vrt'],
  'Egypt': ['al jazeera mubasher', 'extra news', 'nile'],
  'United Arab Emirates': ['al arabiya', 'dubai', 'sky news arabia', 'abu dhabi'],
};

const INTL_RX: Record<string, string[]> = {
  'United States': ['\\bCNN\\b'],
  'United Kingdom': [],
  'Japan': [],
  'South Korea': [],
  'Hong Kong': [],
  'Taiwan': [],
  'France': [],
  'Germany': ['\\bZDF\\b', '\\bARD\\b'],
  'Australia': [],
  'Canada': [],
  'Russia': [],
  'India': [],
  'Singapore': [],
  'Qatar': [],
  'Turkey': [],
  'Switzerland': [],
  'Netherlands': [],
  'Italy': [],
  'Spain': [],
  'Mexico': [],
  'Argentina': [],
  'Brazil': [],
  'Thailand': [],
  'Vietnam': [],
  'Philippines': [],
  'Indonesia': [],
  'Malaysia': [],
  'Saudi Arabia': [],
  'Israel': [],
  'Ukraine': [],
  'Poland': [],
  'Norway': [],
  'Sweden': [],
  'Denmark': [],
  'Austria': [],
  'Belgium': [],
  'Egypt': [],
  'United Arab Emirates': [],
};

const INTL_COUNTRY_NAMES: Record<string, string> = {
  'United States': '美国',
  'United Kingdom': '英国',
  'Japan': '日本',
  'South Korea': '韩国',
  'Hong Kong': '香港',
  'Taiwan': '台湾',
  'France': '法国',
  'Germany': '德国',
  'Australia': '澳大利亚',
  'Canada': '加拿大',
  'Russia': '俄罗斯',
  'India': '印度',
  'Singapore': '新加坡',
  'Qatar': '卡塔尔',
  'Turkey': '土耳其',
  'Switzerland': '瑞士',
  'Netherlands': '荷兰',
  'Italy': '意大利',
  'Spain': '西班牙',
  'Mexico': '墨西哥',
  'Argentina': '阿根廷',
  'Brazil': '巴西',
  'Thailand': '泰国',
  'Vietnam': '越南',
  'Philippines': '菲律宾',
  'Indonesia': '印度尼西亚',
  'Malaysia': '马来西亚',
  'Saudi Arabia': '沙特阿拉伯',
  'Israel': '以色列',
  'Ukraine': '乌克兰',
  'Poland': '波兰',
  'Norway': '挪威',
  'Sweden': '瑞典',
  'Denmark': '丹麦',
  'Austria': '奥地利',
  'Belgium': '比利时',
  'Egypt': '埃及',
  'United Arab Emirates': '阿联酋',
};

/** 判断是否为白名单内的国际台；是则返回中文分组名（如"美国"），否则 null。
 *  纯子串匹配为主（便宜），仅  边界的模式用正则。 */
function intlGroupFor(channel: IPTVChannel): string | null {
  const plain = INTL_PLAIN[channel.group];
  const rx = INTL_RX[channel.group];
  if (!plain && !rx) return null;
  const lower = channel.name.toLowerCase();
  if (plain) {
    for (const p of plain) {
      if (lower.includes(p)) return INTL_COUNTRY_NAMES[channel.group] ?? channel.group;
    }
  }
  if (rx) {
    for (const r of rx) {
      if (new RegExp(r, "i").test(channel.name)) return INTL_COUNTRY_NAMES[channel.group] ?? channel.group;
    }
  }
  return null;
}

async function readIPTVCache(
  env: Env,
  key = IPTV_CACHE_KEY,
  allowStale = false
): Promise<{ channels: IPTVChannel[]; updatedAt: number } | null> {
  try {
    const res = await env.DB.prepare(
      "SELECT data, updated_at FROM trending_cache WHERE id = ?"
    ).bind(key).first<{ data: string; updated_at: number }>();
    if (!res?.data) return null;
    const now = Math.floor(Date.now() / 1000);
    if (!allowStale && now - Number(res.updated_at) > IPTV_CACHE_TTL_SECONDS) return null;
    const parsed = JSON.parse(res.data);
    if (!Array.isArray(parsed)) return null;
    return { channels: parsed as IPTVChannel[], updatedAt: Number(res.updated_at) };
  } catch {
    return null;
  }
}

async function writeIPTVCache(env: Env, channels: IPTVChannel[], key = IPTV_CACHE_KEY): Promise<void> {
  try {
    await env.DB.prepare(
      "INSERT INTO trending_cache (id, data, updated_at) VALUES (?, ?, ?) " +
      "ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at"
    ).bind(key, JSON.stringify(channels), Math.floor(Date.now() / 1000)).run();
  } catch {
    // 缓存写入失败不阻塞响应
  }
}

/** 台名清洗：去横杠/空格/下划线后小写，用于合并同一台的不同写法（CCTV-1 与 CCTV1）。 */
function cleanChannelName(name: string): string {
  return name.replace(/[\s\-_]+/g, "").toLowerCase();
}

/** 频道去重：先按 URL，再按清洗后的台名合并（同一台保留一个变体）。
 *  preferReachable=true（网页）：优先保留探测可达的变体（绕过地理封锁），其次 https，最后第一个；
 *  preferReachable=false（App）：保留第一个源——国内响应最快的源，App 直连可用。 */
function dedupeIPTVChannels(channels: IPTVChannel[], preferReachable: boolean): IPTVChannel[] {
  const seenURL = new Set<string>();
  const byName = new Map<string, IPTVChannel[]>();
  for (const ch of channels) {
    if (seenURL.has(ch.url)) continue;
    seenURL.add(ch.url);
    const key = cleanChannelName(ch.name);
    if (!byName.has(key)) byName.set(key, []);
    byName.get(key)!.push(ch);
  }
  const out: IPTVChannel[] = [];
  for (const list of byName.values()) {
    if (preferReachable) {
      const reachable = list.find((c) => c.reachable === true);
      const https = list.find((c) => c.url.startsWith("https://"));
      out.push(reachable ?? https ?? list[0]);
    } else {
      out.push(list[0]);
    }
  }
  return out;
}

/** 探测单个频道从 Cloudflare 网络是否可达（拉取播放列表头即可，8s 超时——国内源经 Cloudflare 国际网络首字节常需 1~3s）。 */
async function probeIPTVChannel(channel: IPTVChannel): Promise<IPTVChannel> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const resp = await fetch(channel.url, {
      headers: { "user-agent": "Mozilla/5.0", accept: "*/*" },
      signal: controller.signal,
    });
    clearTimeout(timer);
    const ok = resp.ok;
    await resp.body?.cancel();
    return { ...channel, reachable: ok };
  } catch {
    clearTimeout(timer);
    return { ...channel, reachable: false };
  }
}

/** 每轮最多探测的主机数。免费档单次调用 50 次外部子请求上限（刷新本身还要抓 3 个源），
 *  留余量取 40；剩余主机由后续请求的 backfill 按"未标记频道"分批补探测，2~3 轮收敛。 */
const IPTV_PROBE_HOST_CAP = 40;

/** 按主机探测可达性（16 并发 × 8s 超时）。地理封锁是主机级（同 IP:port 的所有流同生死），
 *  每主机取第一个 URL 探测（够判定主机级封锁）。 */
async function probeIPTVHosts(urls: string[], relay?: string): Promise<Map<string, boolean>> {
  const byHost = new Map<string, string>();
  for (const u of urls) {
    try {
      const host = new URL(u).host;
      if (!byHost.has(host)) byHost.set(host, u);
    } catch {
      // 非法 URL 忽略
    }
  }
  const result = new Map<string, boolean>();
  const entries = [...byHost.entries()].slice(0, IPTV_PROBE_HOST_CAP);
  for (let i = 0; i < entries.length; i += 16) {
    const batch = entries.slice(i, i + 16);
    const res = await Promise.all(
      batch.map(async ([host, url]) => {
        // 经中转探测：把探测目标换成 relay 的 /proxy 入口（中转在国内网络，不受地理封锁影响）。
        const probeURL = relay ? `${relay}/proxy?url=${encodeURIComponent(url)}` : url;
        const probe = await probeIPTVChannel({ name: host, url: probeURL, logo: null, group: "", responseTime: "" });
        return [host, probe.reachable === true] as const;
      })
    );
    for (const [h, ok] of res) result.set(h, ok);
  }
  return result;
}

/** 按主机判定给频道打 reachable 标记（URL 解析失败则保持未标记）。 */
function markHostReachability(channels: IPTVChannel[], hostMap: Map<string, boolean>): IPTVChannel[] {
  return channels.map((ch) => {
    try {
      const r = hostMap.get(new URL(ch.url).host);
      if (r !== undefined) return { ...ch, reachable: r };
    } catch {
      // 忽略非法 URL
    }
    return ch;
  });
}

/** 网页模式兜底：分批补探测主机并写回缓存（受 50 外部子请求上限约束，多轮收敛）。
 *  国内台：配置中转时经中转重探（中转在国内网络，能访问被地理封锁的源）。
 *  国际台：只直连探测（中转在国内网络，反而够不到国外源）；标记后网页端灰显不可播的台。 */
async function backfillIPTVReachability(env: Env, cacheKey: number): Promise<void> {
  const cached = await readIPTVCache(env, cacheKey, true);
  if (!cached) return;
  const intlSet = new Set(Object.values(INTL_COUNTRY_NAMES));
  const domestic = cached.channels.filter((ch) => !intlSet.has(ch.group));
  const intl = cached.channels.filter((ch) => intlSet.has(ch.group));
  // 每轮国内 20 + 国际 20 = 40 次子请求，两批合计不超 50 上限；剩余下一轮继续。
  // 国内台：配置了中转时重探"非直连可达"（直连被拒的经中转救活）；无中转时只探未标记的（避免反复重探已判定失败的）。
  // 国际台：只探未标记的（直连失败即失败，没有中转可救）。
  const dNeeds = (env.IPTV_RELAY_URL
    ? domestic.filter((ch) => ch.reachable !== true)
    : domestic.filter((ch) => ch.reachable === undefined)
  ).slice(0, 20);
  const iNeeds = intl.filter((ch) => ch.reachable === undefined).slice(0, 20);
  if (dNeeds.length === 0 && iNeeds.length === 0) return;
  const dMap = await probeIPTVHosts(dNeeds.map((ch) => ch.url), env.IPTV_RELAY_URL);
  const iMap = await probeIPTVHosts(iNeeds.map((ch) => ch.url));
  const marked = [...markHostReachability(domestic, dMap), ...markHostReachability(intl, iMap)];
  await writeIPTVCache(env, marked, cacheKey);
}

/** 解析 m3u8 播放列表文本 → 频道数组（#EXTINF 行 + 下一行 URL 配对）。 */
function parseIPVPlaylist(text: string): IPTVChannel[] {
  const lines = text.split(/\r?\n/);
  const channels: IPTVChannel[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line.startsWith("#EXTINF")) continue;
    const nameMatch = line.match(/,\s*([^,]+)\s*$/);
    const name = nameMatch ? nameMatch[1].trim() : "";
    if (!name) continue;
    const logoMatch = line.match(/tvg-logo="([^"]*)"/);
    const groupMatch = line.match(/group-title="([^"]*)"/);
    const timeMatch = line.match(/response-time="([^"]*)"/);
    let url = "";
    for (let j = i + 1; j < lines.length; j++) {
      const next = lines[j].trim();
      if (!next || next.startsWith("#")) break;
      url = next;
      break;
    }
    if (!url) continue;
    channels.push({
      name,
      logo: logoMatch ? logoMatch[1] : null,
      url,
      group: groupMatch ? groupMatch[1] : "其他",
      responseTime: timeMatch ? timeMatch[1] : "",
    });
  }
  return channels;
}

/** 重新抓取源站并写缓存（handleIPTV 首次请求与 stale 回退共用）。返回抓取到的频道（可能为空）。 */
async function refreshIPTV(env: Env, ctx: ExecutionContext, cacheKey: number, preferReachable: boolean): Promise<IPTVChannel[]> {
  // 国内/港台源：内置列表（2026-08-18 本地网络实测 151 台全可播，含台标）。
  // 直接标记 reachable=true：可达性探测从 Cloudflare 网络发起，对国内裸流 IP（119.233.255.62:1234 等）
  // 会误判不可达，而实际播放是浏览器/App 用户网络直连，探测结果无参考价值（2026-08-18 线上 bug 修复）。
  const domestic: IPTVChannel[] = parseIPVPlaylist(IPTV_BUILTIN_M3U).map((ch) => ({ ...ch, reachable: true }));
  // 国际台：抓 iptv-org 全球列表，按国家白名单过滤知名台，分组名归一为中文国家名。
  // 只保留 http(s) 流（worker fetch 不支持 rtmp 等协议）。
  const intl: IPTVChannel[] = [];
  for (const src of IPTV_INTL_SOURCES) {
    try {
      const resp = await fetch(src.url, {
        headers: { "user-agent": "Mozilla/5.0" },
      });
      if (resp.ok) {
        const text = await resp.text();
        for (const ch of parseIPVPlaylist(text)) {
          const g = intlGroupFor(ch);
          if (g && /^https?:\/\//i.test(ch.url)) {
            ch.group = g;
            intl.push(ch);
          }
        }
      }
    } catch {
      // 单源失败不阻塞
    }
  }
  const intlDeduped = dedupeIPTVChannels(intl, preferReachable);
  const allVariants = [...domestic, ...intlDeduped];
  if (allVariants.length > 0) {
    await writeIPTVCache(env, allVariants, cacheKey);
    // 国内/港台为内置源且已标记可达，不再从 Cloudflare 探测（探测网络与用户网络不同，误判不可达）。
    // 国际台不探测（300+ 且部分地理封锁，30s 预算不够；保持"未探测=可点播"）。
  }
  // 响应按台名去重（网页模式：有可达标记时优先可达变体；首次请求探测未完成则 https/首个）。
  return dedupeIPTVChannels(allVariants, preferReachable);
}

/** GET /api/iptv 返回分组频道列表。 */
async function handleIPTV(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const reqURL = new URL(request.url);
  // App 模式（?app=1）：保留国内最快源，App 直连播放；网页模式：优先可达变体 + https + 可达性标记。
  const isApp = reqURL.searchParams.get("app") === "1";
  const cacheKey = isApp ? IPTV_CACHE_KEY_APP : IPTV_CACHE_KEY;
  const preferReachable = !isApp;
  let channels: IPTVChannel[] | null = null;
  let updatedAt = Math.floor(Date.now() / 1000);
  const fresh = await readIPTVCache(env, cacheKey);
  if (fresh) {
    channels = dedupeIPTVChannels(fresh.channels, preferReachable);
    updatedAt = fresh.updatedAt;
    // 网页缓存未全部标记（探测按 50 外部子请求上限分批进行）→ 后台补探测下一批主机，不阻塞响应。
    if (!isApp && !channels.every((c) => c.reachable !== undefined)) {
      ctx.waitUntil(backfillIPTVReachability(env, cacheKey));
    }
  } else {
    // 缓存过期或缺失：先尝试过期缓存（stale）响应，避免源站抖动导致列表清空；后台刷新。
    const stale = await readIPTVCache(env, cacheKey, true);
    if (stale) {
      channels = dedupeIPTVChannels(stale.channels, preferReachable);
      updatedAt = stale.updatedAt;
      ctx.waitUntil(refreshIPTV(env, ctx, cacheKey, preferReachable));
    }
  }
  if (!channels) {
    channels = await refreshIPTV(env, ctx, cacheKey, preferReachable);
    updatedAt = Math.floor(Date.now() / 1000);
  }
  if (channels.length === 0) {
    return new Response(JSON.stringify({ groups: [], total: 0, updatedAt: updatedAt * 1000 }), {
      status: 200,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=60" },
    });
  }
  // App 模式：国际台国内网络直连不通，URL 改走 worker 流代理（网页端由客户端统一包代理，这里不动）。
  if (isApp) {
    const intlGroups = new Set(Object.values(INTL_COUNTRY_NAMES));
    const origin = `${reqURL.protocol}//${reqURL.host}`;
    channels = channels.map((ch) =>
      intlGroups.has(ch.group) ? { ...ch, url: `${origin}/api/iptv/stream?url=${encodeURIComponent(ch.url)}` } : ch
    );
  }
  // 网页模式：标记 Cloudflare 网络不可达的源（实测 119.233.255.62 央视/卫视 34 台），
  // 网页端播放走 worker 代理（Cloudflare 网络）必然 502；App 端直连不受限（2026-08-18 修复）。
  if (!isApp) {
    const WEB_UNPLAYABLE_HOSTS = ["119.233.255.62"];
    channels = channels.map((ch) =>
      WEB_UNPLAYABLE_HOSTS.some((h) => ch.url.includes(h)) ? { ...ch, webUnplayable: true } : ch
    );
  }
  // 分组名归一：源里同一分组叫法不统一（央视台/央视频道、其他/其他频道），统一展示；
  // 台名含 CCTV/央视 的一律归入央视频道（源里 CCTV-5+ 等可能被标到其他分组）。
  const normalizeGroup = (raw: string, name: string): string => {
    if (/cctv|央视/i.test(name)) return "央视频道";
    if (raw === "央视台") return "央视频道";
    if (raw === "其他频道") return "其他";
    return raw;
  };
  // 按分组聚合并保留原始顺序。
  const groups: { name: string; channels: IPTVChannel[] }[] = [];
  const seen = new Map<string, number>();
  for (const ch of channels) {
    const g = normalizeGroup(ch.group || "其他", ch.name);
    const channel = { ...ch, group: g };
    if (!seen.has(g)) {
      seen.set(g, groups.length);
      groups.push({ name: g, channels: [] });
    }
    groups[seen.get(g)!].channels.push(channel);
  }
  // 组内按可达性排序（可播在前）。分组顺序：国内组保持源顺序在前，国际组按频道数降序（大组靠前）。
  if (!isApp) {
    for (const g of groups) {
      g.channels.sort((a, b) => (b.reachable === true ? 1 : 0) - (a.reachable === true ? 1 : 0));
    }
  }
  const intlNameSet = new Set(Object.values(INTL_COUNTRY_NAMES));
  groups.sort((a, b) => {
    const ai = intlNameSet.has(a.name) ? 1 : 0;
    const bi = intlNameSet.has(b.name) ? 1 : 0;
    if (ai !== bi) return ai - bi; // 国内组在前
    if (ai === 1) return b.channels.length - a.channels.length; // 国际组按频道数降序（稳定排序保持同数原序）
    return 0;
  });
  return new Response(
    JSON.stringify({ groups, total: channels.length, updatedAt: updatedAt * 1000 }),
    {
      status: 200,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=600" },
    }
  );
}

/** 拉取直播流上游：直连优先；失败/被拒且配置了国内中转时经中转拉取（绕过地理封锁）。
 *  relay 为 CineBarRelay 的 /proxy 入口（如 https://xxx.trycloudflare.com）。 */
async function fetchIPTVUpstream(target: string, relay?: string): Promise<Response> {
  const headers = { "user-agent": "Mozilla/5.0", accept: "*/*" };
  let resp: Response;
  try {
    resp = await fetch(target, { headers });
  } catch {
    resp = new Response("upstream unreachable", { status: 502 });
  }
  if (!resp.ok && relay) {
    // 直连 403/失败 → 走国内中转（中转机在国内网络，可访问被地理封锁的源）
    resp = await fetch(`${relay}/proxy?url=${encodeURIComponent(target)}`, { headers }).catch(
      () => new Response("relay unreachable", { status: 502 })
    );
  }
  return resp;
}

/** 把播放列表/分片里的 URI 重写为经本 worker 代理的绝对地址（解决 http 源在 https 页面的混合内容 + CORS）。 */
function rewritePlaylistURIs(text: string, baseURL: URL, origin: string): string {
  const proxy = (ref: string): string => {
    let absolute: string;
    try {
      absolute = new URL(ref, baseURL).toString();
    } catch {
      return ref;
    }
    return `${origin}/api/iptv/stream?url=${encodeURIComponent(absolute)}`;
  };
  return text
    .split(/\r?\n/)
    .map((line) => {
      const trimmed = line.trim();
      // #EXT-X-KEY:METHOD=AES-128,URI="..."
      let m = trimmed.match(/^(#EXT-X-KEY:.*URI=")([^"]+)(".*)$/);
      if (m) return m[1] + proxy(m[2]) + m[3];
      // #EXT-X-MAP:URI="..."
      m = trimmed.match(/^(#EXT-X-MAP:.*URI=")([^"]+)(".*)$/);
      if (m) return m[1] + proxy(m[2]) + m[3];
      // 分片/子清单行（非注释、非空）
      if (trimmed && !trimmed.startsWith("#")) return proxy(trimmed);
      return line;
    })
    .join("\n");
}

/** GET /api/iptv/stream?url=…  HLS 直播代理：服务端拉取 http 源，重写分片地址为同源代理，解决混合内容与 CORS。
 *  直连失败时自动回退到国内中转（IPTV_RELAY_URL），让被地理封锁的国内台也能播。 */
async function handleIPTVStream(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const target = url.searchParams.get("url");
  if (!target) {
    return new Response("missing url", { status: 400 });
  }
  const upstream = await fetchIPTVUpstream(target, env.IPTV_RELAY_URL);
  if (!upstream.ok) {
    return new Response(`upstream ${upstream.status}`, { status: 502 });
  }
  const contentType = upstream.headers.get("content-type") || "application/octet-stream";
  const text = await upstream.text();
  const origin = `${url.protocol}//${url.host}`;
  const body = text.startsWith("#EXTM3U") || contentType.includes("mpegurl")
    ? rewritePlaylistURIs(text, new URL(target), origin)
    : text;
  return new Response(body, {
    status: 200,
    headers: {
      "content-type": contentType,
      "access-control-allow-origin": "*",
      "cache-control": "no-store",
    },
  });
}

/** GET /api/iptv/logo?url=…  台标代理：绕开 gitee 防盗链（带 Referer 会 403），并加 CORS。 */
async function handleIPTVLogo(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const target = url.searchParams.get("url");
  if (!target) {
    return new Response("missing url", { status: 400 });
  }
  let upstream: Response;
  try {
    // 不转发任何 Referer，避免 gitee 等源站防盗链拦截。
    upstream = await fetch(target, {
      headers: { "user-agent": "Mozilla/5.0", accept: "image/*" },
    });
  } catch {
    return new Response("upstream unreachable", { status: 502 });
  }
  if (!upstream.ok) {
    return new Response(`upstream ${upstream.status}`, { status: 502 });
  }
  const contentType = upstream.headers.get("content-type") || "image/png";
  const buf = await upstream.arrayBuffer();
  return new Response(buf, {
    status: 200,
    headers: {
      "content-type": contentType,
      "access-control-allow-origin": "*",
      "cache-control": "public, max-age=86400",
    },
  });
}

async function handleTrending(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const url = new URL(request.url);
  const type = normalizeText(url.searchParams.get("type")) || "all";
  const wantMovie = type === "all" || type === "movie";
  const wantTV = type === "all" || type === "tv";

  const cached = await readTrendingCache(env);
  const payload: Record<string, TrendingMovie[]> = {};

  // stale-while-revalidate：有缓存（即使过期）立即返回，过期则后台刷新，避免用户等 25 秒。
  if (cached && (cached.movies.length > 0 || cached.shows.length > 0)) {
    if (wantMovie) payload.movies = cached.movies;
    if (wantTV) payload.shows = cached.shows;
    if (!cached.fresh) {
      ctx.waitUntil(refreshTrendingCache(env, wantMovie, wantTV));
    }
    return new Response(
      JSON.stringify(payload),
      { status: 200, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=3600" } }
    );
  }

  // 无缓存：同步刷新（首次访问会稍慢，后续走 stale 秒回）。
  const result = await refreshTrendingCache(env, wantMovie, wantTV);
  if (!result) {
    return new Response(
      JSON.stringify({ error: "trending unavailable" }),
      { status: 502, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } }
    );
  }
  if (wantMovie) payload.movies = result.movies;
  if (wantTV) payload.shows = result.shows;
  return new Response(
    JSON.stringify(payload),
    { status: 200, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=3600" } }
  );
}

/** 拉取 Moovie discover 热门 + 补 tmdbId + 写缓存。返回 null 表示 Moovie 不可达。 */async function refreshTrendingCache(
  env: Env,
  wantMovie: boolean,
  wantTV: boolean
): Promise<{ movies: TrendingMovie[]; shows: TrendingMovie[] } | null> {
  const [movieHtml, tvHtml] = await Promise.all([
    wantMovie ? moovieFetch("/discover/movie") : Promise.resolve(null),
    wantTV ? moovieFetch("/discover/tv") : Promise.resolve(null),
  ]);
  if (wantMovie && !movieHtml) return null;
  if (wantTV && !tvHtml) return null;

  const movies = movieHtml ? parseTrendingMovies(movieHtml) : [];
  let shows = tvHtml ? parseTrendingMovies(tvHtml) : [];

  // Moovie /discover/tv 改版后常返回空（shows=0），用 CineCMS 电视剧列表兜底（有海报，可点进 /watch）。
  if (shows.length === 0) {
    try {
      const list = await cmsListByCategory("tv", 1);
      shows = list.items.slice(0, 10).map((x) => ({
        title: x.title,
        doubanID: `${x.source}|${x.id}`,
        rating: 0,
        poster: x.poster ?? "",
        type: "tv" as const,
      }));
    } catch { shows = []; }
  }

  // 为每部片补齐 tmdbId/type（前 10 部，并行控请求量）。
  async function enrich(list: TrendingMovie[]) {
    await Promise.all(list.slice(0, 10).map(async (item) => {
      let moovieYear = "";
      try {
        const params = new URLSearchParams({ q: item.title });
        const resp = await moovieFetch(`/api/htmx/search?${params}`);
        if (resp) {
          const cardPattern = /href="(\/play\/[^"]*douban_id=(\d+)[^"]*)"/g;
          let cm;
          while ((cm = cardPattern.exec(resp)) !== null) {
            if (cm[2] === item.doubanID) {
              const card = resp.slice(cm.index, cm.index + 1200);
              const ym = card.match(/card-year">([^<]*)</);
              if (ym) { moovieYear = ym[1].trim(); }
              break;
            }
          }
        }
      } catch { moovieYear = ""; }
      const info = await cineaiTMDBInfo(item.title, env, moovieYear);
      if (info.length > 0 && info[0].tmdbId) {
        item.tmdbId = info[0].tmdbId;
        item.type = info[0].mediaType;
        // 补 TMDB 海报（更稳定，Moovie 豆瓣图代理偶尔失败）。
        const key = env?.TMDB_API_KEY;
        if (key) {
          try {
            const kind = item.type === "tv" ? "tv" : "movie";
            const res = await fetch(
              `https://api.themoviedb.org/3/${kind}/${item.tmdbId}?api_key=${key}&language=zh-CN`,
              { headers: { "user-agent": "Mozilla/5.0" } }
            );
            if (res.ok) {
              const dd = (await res.json()) as { poster_path?: string | null };
              if (dd.poster_path) item.tmdbPoster = `https://image.tmdb.org/t/p/w342${dd.poster_path}`;
            }
          } catch { /* 忽略 */ }
        }
      }
    }));
  }
  await Promise.all([enrich(movies), enrich(shows)]);

  await writeTrendingCache(env, movies, shows);
  return { movies, shows };
}

/** GET /api/nowplaying-cn 返回国内院线正在热映的电影（豆瓣 cinema/nowplaying，更贴近国内上映）。 */
async function handleNowPlayingCN(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const origin = `${url.protocol}//${url.host}`;
  try {
    const resp = await fetch("https://movie.douban.com/cinema/nowplaying/beijing/", {
      headers: { "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36" },
      redirect: "follow",
    });
    if (!resp.ok) {
      return new Response(JSON.stringify({ error: "upstream" }), { status: 502, headers: { "content-type": "application/json; charset=utf-8" } });
    }
    const html = await resp.text();
    const items = parseDoubanNowPlaying(html, origin);
    return new Response(
      JSON.stringify({ items }),
      { status: 200, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=3600" } }
    );
  } catch {
    return new Response(JSON.stringify({ error: "failed" }), { status: 500, headers: { "content-type": "application/json; charset=utf-8" } });
  }
}

/** 解析豆瓣 cinema/nowplaying 条目：标题、评分、上映年份、海报（经本站代理绕防盗链）。 */
function parseDoubanNowPlaying(html: string, origin: string): { title: string; year: string; rating: number | null; poster: string | null }[] {
  const items: { title: string; year: string; rating: number | null; poster: string | null }[] = [];
  const lis = html.match(/<li\b[^>]*data-subject="\d+"[^>]*>.*?<\/li>/gs) ?? [];
  for (const li of lis) {
    const title = (li.match(/data-title="([^"]*)"/) ?? [])[1] ?? "";
    const score = (li.match(/data-score="([^"]*)"/) ?? [])[1] ?? "";
    const release = (li.match(/data-release="([^"]*)"/) ?? [])[1] ?? "";
    const posterMatch = li.match(/<img[^>]*src="([^"]*\.(?:jpg|png))"/);
    const year = release.slice(0, 4);
    if (!title) continue;
    items.push({
      title: title.trim(),
      year,
      rating: score && Number(score) > 0 ? Number(score) : null,
      poster: posterMatch ? `${origin}/api/cms/poster?url=${encodeURIComponent(posterMatch[1])}` : null,
    });
    if (items.length >= 12) break;
  }
  return items;
}

/** GET /api/nowplaying 返回正在院线热映的电影（TMDB movie/now_playing，取前 10，含海报/年份/评分）。 */
async function handleNowPlaying(request: Request, env: Env): Promise<Response> {
  const key = env?.TMDB_API_KEY;
  if (!key) {
    return new Response(JSON.stringify({ error: "no key" }), {
      status: 503,
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
  try {
    const params = new URLSearchParams({ language: "zh-CN", page: "1", region: "CN", api_key: key });
    const resp = await fetch(`https://api.themoviedb.org/3/movie/now_playing?${params}`, {
      headers: { "user-agent": "Mozilla/5.0" },
    });
    if (!resp.ok) {
      return new Response(JSON.stringify({ error: "upstream" }), {
        status: 502,
        headers: { "content-type": "application/json; charset=utf-8" },
      });
    }
    const data = (await resp.json()) as { results?: Record<string, unknown>[] };
    const items = (data.results ?? []).slice(0, 10).map((r) => ({
      title: r.title ?? "",
      year: String(r.release_date ?? "").slice(0, 4),
      rating: r.vote_average ?? null,
      poster: r.poster_path ? `https://image.tmdb.org/t/p/w342${r.poster_path}` : null,
      overview: r.overview ?? "",
    }));
    return new Response(
      JSON.stringify({ items }),
      { status: 200, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=3600" } }
    );
  } catch {
    return new Response(JSON.stringify({ error: "failed" }), {
      status: 500,
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
}

/** CineAI 服务端代理转发：浏览器把 { device, messages } 发给本站，
 *  本站转发到 cineai.cinebar.cc（保管 DeepSeek key 的限额代理），
 *  拿回回答。key 永远不进浏览器，也不进本站代码。
 *
 *  本站强制做与 App 版一致的「调校」，防止 CineAI 被当通用 AI 越界使用：
 *   1. offScope 越界拦截：写代码/写文章/翻译等本地硬拦截，不调模型、不耗 token。
 *   2. 意图路由：findMovie / mediaIntro / recommend / spoilerSafe / general 各用不同
 *      system prompt，hard 约束"只做影视"。
 *   3. 回答原则：候选资料只是参考，缺资料用 DeepSeek 影视知识回答，不拒绝。
 *   4. 回答完即止：prompt 禁止反问/引导继续对话。
 *   5. 历史裁剪：最近 6 条 + 总字符 ≤3000 + 单条 ≤800，防代理 413。
 */
const CINEAI_PROXY_URL = "https://cineai.cinebar.cc/v1/chat/completions";
const CINEAI_MAX_INPUT_CHARS = 8000;
const CINEAI_MAX_MESSAGES = 30;

/** GET /api/lookup?title= 用 TMDB 查一部片/剧，返回首个匹配（供 CineAI 回答里的
 *  《片名》生成可点击海报小卡）。movie 优先，其次 tv。 */
const TITLE_SYNONYMS: string[][] = [
  ["海贼王", "航海王", "one piece", "ワンピース"],
  ["火影忍者", "naruto"],
  ["死神", "bleach"],
  ["名侦探柯南", "detective conan", "名探偵コナン"],
  ["龙珠", "七龙珠", "dragon ball"],
  ["数码宝贝", "数码暴龙", "digimon"],
  ["宠物小精灵", "神奇宝贝", "精灵宝可梦", "pokemon", "宝可梦"],
  ["高达", "gundam", "機動戦士ガンダム"],
  ["哆啦a梦", "机器猫", "doraemon", "ドラえもん"],
  ["蜡笔小新", "crayon shin-chan", "クレヨンしんちゃん"],
  ["千与千寻", "spirited away", "千と千尋の神隠し"],
  ["龙猫", "my neighbor totoro", "となりのトトロ"],
  ["灌篮高手", "slam dunk"],
  ["进击的巨人", "attack on titan", "進撃の巨人"],
  ["鬼灭之刃", "demon slayer", "鬼滅の刃"],
];
async function handleLookup(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const title = normalizeText(url.searchParams.get("title"));
  const expectYear = normalizeText(url.searchParams.get("year"));
  if (!title || title.length > 120) {
    return new Response(
      JSON.stringify({ error: "invalid title" }),
      { status: 400, headers: { "content-type": "application/json; charset=utf-8" } }
    );
  }
  const key = env.TMDB_API_KEY;
  if (!key) {
    return new Response(
      JSON.stringify({ error: "unavailable" }),
      { status: 503, headers: { "content-type": "application/json; charset=utf-8" } }
    );
  }
  const base = "https://api.themoviedb.org/3";
  const params = new URLSearchParams({ language: "zh-CN", query: title, include_adult: "false", page: "1", api_key: key });
  try {
    const [movieRes, tvRes] = await Promise.all([
      fetch(`${base}/search/movie?${params}`),
      fetch(`${base}/search/tv?${params}`),
    ]);
    const [movieData, tvData] = await Promise.all([
      movieRes.ok ? movieRes.json() : { results: [] },
      tvRes.ok ? tvRes.json() : { results: [] },
    ]);
    const movies = (movieData.results as Record<string, unknown>[]) ?? [];
    const tvs = (tvData.results as Record<string, unknown>[]) ?? [];
    if (movies.length === 0 && tvs.length === 0) {
      return new Response(JSON.stringify({ found: false }), {
        status: 200, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=3600" },
      });
    }
    // 优先精确/开头匹配标题；派生/剧场版/特别篇等衍生作降权，避免匹配到衍生作
    const normalize = (s: unknown) => String(s ?? "").toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
    const nt = normalize(title);
    // 输入的同义词集合（含本身）：解决译名歧义（海贼王↔航海王↔ONE PIECE 等）
    const synonyms = [nt];
    for (const group of TITLE_SYNONYMS) {
      if (group.some((name) => normalize(name) === nt)) {
        for (const name of group) synonyms.push(normalize(name));
        break;
      }
    }
    const DERIVATIVE_WORDS = ["剧场版", "特别篇", "女英雄", "纪念", "番外", "合集", "故事集", "sp", "special", "外传", "前传", "短篇", "ova"];
    const isDerivative = (n: string) => DERIVATIVE_WORDS.some((w) => n.includes(w));
    const yearOf = (r: Record<string, unknown>) => String(r.release_date ?? r.first_air_date ?? "").slice(0, 4);
    const score = (r?: Record<string, unknown>, kind?: "movie" | "tv") => {
      if (!r) return -1;
      // 同时匹配中文标题与原片名（支持中英文输入）
      const names = [r.title, r.name, r.original_title, r.original_name]
        .filter((x): x is string => !!x)
        .map(normalize);
      const n = names[0] ?? "";
      let s = 0;
      for (const candidate of names) {
        if (synonyms.includes(candidate)) { s = 3; break; }
        if (synonyms.some((sy) => candidate.startsWith(sy))) { s = Math.max(s, 2); continue; }
        if (synonyms.some((sy) => candidate.includes(sy) || sy.includes(candidate))) s = Math.max(s, 1);
      }
      // 年份一致优先：区分同名不同年份的作品
      if (s > 0 && expectYear && yearOf(r) === expectYear) {
        s += 1;
      }
      // movie 的剧场版/特别篇等衍生作，或任何明确的衍生作：直接排除（避免匹配到衍生作）
      if (isDerivative(n) && (kind === "movie" || s > 0)) {
        return 0;
      }
      return s;
    };
    const pickMovie = movies.length > 0 ? [...movies].sort((a, b) => {
      const d = score(b, "movie") - score(a, "movie");
      if (d !== 0) return d;
      // 同分时优先最早年份（主剧/系列第一部通常最早）
      const ay = String(a.release_date ?? "").slice(0, 4) || "9999";
      const by = String(b.release_date ?? "").slice(0, 4) || "9999";
      return ay.localeCompare(by);
    })[0] : undefined;
    const pickTV = tvs.length > 0 ? [...tvs].sort((a, b) => {
      const d = score(b, "tv") - score(a, "tv");
      if (d !== 0) return d;
      const ay = String(a.first_air_date ?? "").slice(0, 4) || "9999";
      const by = String(b.first_air_date ?? "").slice(0, 4) || "9999";
      return ay.localeCompare(by);
    })[0] : undefined;
    const mv = score(pickMovie, "movie");
    const tv = score(pickTV, "tv");
    // 分数高者胜；同分时优先 tv（连续剧语境，避免被衍生剧场版 movie 顶掉）
    const useMovie = mv > tv || (mv === tv && tv < 0);
    const item = (useMovie && pickMovie) ? pickMovie : pickTV;
    if (!item) {
      return new Response(JSON.stringify({ found: false }), {
        status: 200, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=3600" },
      });
    }
    const itemTitle = String(item.title ?? item.name ?? "");
    const itemYear = String(item.release_date ?? item.first_air_date ?? "").slice(0, 4);
    // 查 Moovie 可看性：有候选在线播放源即可看（优先匹配影视库资源）。
    // 用独立短超时，失败快速降级为不可看，不影响 lookup 主流程。
    let playable = false;
    let mooviePath = "";
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 4000);
      // 用中文同义词查 Moovie（Moovie 是中文站，英文名搜不到）
      const zhName = synonyms.find((s) => /[\u4e00-\u9fff]/.test(s)) ?? itemTitle;
      const params = new URLSearchParams({ q: zhName });
      if (itemYear) params.set("year", itemYear);
      const moovieRes = await fetch(`https://moovie.c2v2.com/api/htmx/search?${params}`, {
        headers: { "user-agent": MOOVIE_UA, "hx-request": "true", accept: "text/html,application/xhtml+xml" },
        signal: controller.signal,
      });
      clearTimeout(timer);
      if (moovieRes.ok) {
        const html = await moovieRes.text();
        const candidates = moovieParseResults(html, zhName);
        if (candidates.length > 0) {
          playable = true;
          mooviePath = candidates[0].playPath;
        }
      }
    } catch {
      playable = false;
    }
    return new Response(JSON.stringify({
      found: true,
      type: (useMovie && pickMovie) ? "movie" : "tv",
      id: item.id,
      title: itemTitle,
      year: itemYear,
      poster: item.poster_path ? `https://image.tmdb.org/t/p/w185${item.poster_path}` : null,
      playable,
      playPath: mooviePath,
      dbg_expectYear: expectYear,
      dbg_itemYear: String(item.release_date ?? item.first_air_date ?? "").slice(0, 4),
    }), {
      status: 200, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=3600" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ error: "unavailable", detail: String(e) }),
      { status: 502, headers: { "content-type": "application/json; charset=utf-8" } }
    );
  }
}

const CINEAI_OFFSCOPE_REPLY =
  "我是 CineAI，CineBar 的影视助手，专注于找片、影视问答、推荐和无剧透陪伴。" +
  "写推文、改文章、写代码这类通用任务我帮不了你，不过如果你有想找的电影、想了解某部片、" +
  "或需要按心情推荐，尽管告诉我～";

// CineAI 联网工具：模型可自主调用 web_search 查未上映/冷门/资料缺失的影片，
// 而不是凭过时记忆断言"不存在"。
const CINEAI_WEB_TOOLS = [
  {
    type: "function",
    function: {
      name: "web_search",
      description:
        "联网搜索一部影片的真实资料（上映日期、剧情、未上映/定档信息等）。" +
        "当用户询问的影片你印象中不存在、或可能是新片/未上映/冷门片、或用户明确要求联网搜索时，调用此工具获取真实信息。" +
        "输入要带上片名（尽量完整），系统会调用百度/豆瓣等搜索引擎返回结果。",
      parameters: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "要搜索的影片名称或关键词，如：小黄人与大怪兽",
          },
        },
        required: ["query"],
      },
    },
  },
];

const CINEAI_OFFSCOPE_KEYWORDS = [
  "写推文", "写一篇推文", "发条推文", "写微博", "写小红书",
  "写文章", "写篇文案", "写文案", "写标题", "写简介文案",
  "改文章", "修改文章", "润色", "改写这段", "改写这篇文章",
  "修改这篇文章", "改这篇", "修改这篇", "帮我改", "帮我润色",
  "写代码", "编程", "写程序", "debug", "调 bug", "修复代码",
  "代码", "python", "javascript", "swift代码",
  "写邮件", "写简历", "写合同", "写报告", "写论文", "写作业",
  "翻译", "算一下", "计算", "写诗", "写歌词", "写小说",
  "写故事", "写原创", "写剧本", "写情节", "写台词", "写作",
  "创作灵感", "汲取灵感", "想写个故事", "写背景故事", "想创作",
];

const CINEAI_OFFSCOPE_VERBS = [
  "写", "创作", "润色", "改写", "修改", "改", "编", "生成",
  "翻译", "算", "计算", "编个", "起个", "想个", "拟", "策划",
  "起草", "整理", "总结", "总结一下", "提炼",
];

const CINEAI_OFFSCOPE_OBJECTS = [
  "故事", "剧本", "小说", "文章", "文案", "推文", "微博", "小红书",
  "代码", "程序", "脚本", "邮件", "简历", "合同", "报告", "论文",
  "作业", "歌词", "诗歌", "台词", "标题", "宣传语", "简介",
  "方案", "策划", "提纲", "大纲", "总结", "摘要", "提纲挈领",
];

const CINEAI_THEME_WORDS = [
  "运动", "励志", "热血", "治愈", "温情", "悬疑", "烧脑", "科幻",
  "爱情", "浪漫", "犯罪", "警匪", "古装", "历史", "战争", "灾难",
  "喜剧", "搞笑", "恐怖", "惊悚", "奇幻", "魔幻", "青春", "校园",
  "体育", "足球", "篮球", "拳击", "赛车", "登山", "励志类",
];

const CINEAI_SPOILER_WORDS = [
  "剧透", "结局", "谁死", "最后", "活没活", "死了没", "别剧透",
  "凶手", "真相", "反转", "大结局",
];

const CINEAI_RECOMMEND_WORDS = [
  "今晚看什么", "推荐", "看点什么", "求推荐", "有什么好看", "片单",
];

const CINEAI_INTRO_WORDS = [
  "讲什么", "讲的是", "剧情", "介绍", "简介", "讲述", "这是个",
];

const CINEAI_MEDIA_WORDS = [
  "电影", "影片", "片子", "影视", "动画片", "科幻片", "喜剧片", "剧集", "电视剧",
];

type CineAIIntent =
  | "findMovie" | "spoilerSafe" | "mediaIntro" | "recommend" | "offScope" | "general";

/** 用豆瓣 rexxar 搜索一部片/剧，返回真实资料（标题/年份/评分/类型）。
 *  解决模型知识滞后导致的时效信息（如上映时间）不准问题。 */
async function doubanSearch(title: string): Promise<{ title: string; year: string; rating: number; mediaType: "movie" | "tv" }[]> {
  const q = title.trim().slice(0, 40);
  if (!q) return [];
  const url = `https://m.douban.com/rexxar/api/v2/search?type=movie&q=${encodeURIComponent(q)}`;
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 9000);
    const resp = await fetch(url, {
      headers: {
        "user-agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15",
        referer: "https://m.douban.com/",
      },
      signal: controller.signal,
    });
    clearTimeout(timer);
    if (!resp.ok) return [];
    const data = (await resp.json()) as { subjects?: { items?: { target?: Record<string, unknown> }[] } };
    const items = data?.subjects?.items ?? [];
    const out: { title: string; year: string; rating: number; mediaType: "movie" | "tv" }[] = [];
    for (const it of items.slice(0, 3)) {
      const t = it.target ?? {};
      const name = String(t.title ?? "");
      if (!name) continue;
      const ratingObj = t.rating as Record<string, unknown> | undefined;
      out.push({
        title: name,
        year: String(t.year ?? ""),
        rating: Number(ratingObj?.value ?? 0),
        mediaType: t.has_part ? "tv" : "movie",
      });
    }
    return out;
  } catch {
    return [];
  }
}

/** 用 TMDB 查一部片/剧的真实上映信息（CF 边缘可访问，比豆瓣稳）。
 *  返回标题/上映日期/类型/评分，供 mediaIntro 修正模型时效性知识。 */
 async function cineaiTMDBInfo(title: string, env: Env, expectYear?: string): Promise<{ title: string; year: string; rating: number; mediaType: "movie" | "tv"; tmdbId?: number }[]> {
   const q = title.trim().slice(0, 60);
   if (!q) return [];
   const key = env?.TMDB_API_KEY;
   if (!key) return [];
   const base = "https://api.themoviedb.org/3";
   const params = new URLSearchParams({ language: "zh-CN", query: q, include_adult: "false", page: "1", api_key: key });
   try {
     const [movieRes, tvRes] = await Promise.all([
       fetch(`${base}/search/movie?${params}`),
       fetch(`${base}/search/tv?${params}`),
     ]);
     const [movieData, tvData] = await Promise.all([
       movieRes.ok ? movieRes.json() : { results: [] },
       tvRes.ok ? tvRes.json() : { results: [] },
     ]);
     const movies = (movieData.results as Record<string, unknown>[]) ?? [];
     const tvs = (tvData.results as Record<string, unknown>[]) ?? [];
     const normalize = (s: unknown) => String(s ?? "").toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
     const nt = normalize(q);
     const synonyms = [nt];
     for (const group of TITLE_SYNONYMS) {
       if (group.some((name) => normalize(name) === nt)) {
         for (const name of group) synonyms.push(normalize(name));
         break;
       }
     }
     const yearOf = (r: Record<string, unknown>) => String(r.release_date ?? r.first_air_date ?? "").slice(0, 4);
     const match = (r: Record<string, unknown>) => {
       const names = [r.title, r.name, r.original_title, r.original_name].filter((x): x is string => !!x).map(normalize);
       let s = 0;
       for (const c of names) {
         if (synonyms.includes(c)) { s = 3; break; }
         if (synonyms.some((sy) => c.startsWith(sy))) { s = Math.max(s, 2); continue; }
         if (synonyms.some((sy) => c.includes(sy) || sy.includes(c))) s = Math.max(s, 1);
       }
       // 年份一致优先：区分同名不同年份的作品（如《群体》韩国2026 vs 国外1966）
       if (s > 0 && expectYear && yearOf(r) === expectYear) {
         s += 1;
       }
       return s;
     };
     const byScore = (arr: Record<string, unknown>[]) => {
       if (arr.length === 0) return undefined;
       return [...arr].sort((a, b) => match(b) - match(a))[0];
     };
     const bestMovie = byScore(movies);
     const bestTV = byScore(tvs);
     const ms = bestMovie ? match(bestMovie) : 0;
     const ts = bestTV ? match(bestTV) : 0;
     const useMovie = ms > ts || (ms === ts && !bestTV);
     const item = (useMovie && bestMovie) ? bestMovie : bestTV;
     if (!item || match(item) < 1) return [];
     return [{
       title: String(item.title ?? item.name ?? ""),
       year: String(item.release_date ?? item.first_air_date ?? ""),
       rating: Number(item.vote_average ?? 0),
       mediaType: (useMovie && bestMovie) ? "movie" : "tv",
       tmdbId: Number(item.id ?? 0),
     }];
   } catch {
     return [];
   }
 }


function cineAIContains(text: string, anyOf: string[]): boolean {
  return anyOf.some((kw) => text.toLowerCase().includes(kw));
}

/** 从用户输入提取豆瓣搜索词：优先取《片名》内容；否则去掉常见疑问词后取整句。 */
function cineAIMediaSearchTerm(input: string): string {
  const m = input.match(/《([^》]+)》/);
  if (m) return m[1].trim();
  return input
    .replace(/什么时候|何时|上映|定档|的|这部|这部片|这部剧|电影|电视剧|介绍|简介|讲什么/g, "")
    .trim();
}

function cineAIIsOffScope(text: string): boolean {  if (cineAIContains(text, CINEAI_OFFSCOPE_KEYWORDS)) return true;
  const hasVerb = CINEAI_OFFSCOPE_VERBS.some((v) => text.includes(v));
  const hasObject = CINEAI_OFFSCOPE_OBJECTS.some((o) => text.includes(o));
  return hasVerb && hasObject;
}

/** 排名型事实查询：同时含具体年份 + 评分/榜单/票房类关键词。 */
function cineAIIsRankingQuery(text: string): boolean {
  if (!/20[0-9]{2}/.test(text)) return false;
  const rankingWords = [
    "评分最高", "最高分", "高分", "最佳", "榜首", "排名",
    "榜单", "票房冠军", "票房最高", "评分排行", "年度最佳",
    "神作", "top", "豆瓣9分", "豆瓣 9 分",
  ];
  return rankingWords.some((w) => text.toLowerCase().includes(w));
}

function cineAIIntent(text: string): CineAIIntent {
  const t = text.trim();
  if (!t) return "general";
  if (cineAIIsOffScope(t)) return "offScope";
  // 排名型事实查询（年份 + 评分/榜单/票房，如"2025年评分最高的电影"）：
  // 模型知识截止早于近年，必须走 findMovie 并强制联网拿真实榜单，不能凭记忆编。
  if (cineAIIsRankingQuery(t)) return "findMovie";
  if (cineAIContains(t, CINEAI_SPOILER_WORDS)) return "spoilerSafe";
  if (cineAIContains(t, CINEAI_RECOMMEND_WORDS)) return "recommend";
  if (cineAIContains(t, [...CINEAI_INTRO_WORDS, "上映", "何时上映", "什么时候上映", "什么时候上", "定档", "上映时间", "开拍", "何时"])) {
    return "mediaIntro";
  }
  if (cineAIContains(t, CINEAI_MEDIA_WORDS)) return "findMovie";
  if (cineAIContains(t, ["找一部", "有没有类似", "推荐一部"])) return "findMovie";
  return "general";
}

/** 按意图构建带 system prompt 的 messages，并插入裁剪后的历史。
 *  所有意图统一强制"纯文本、去 markdown 符号"的格式约束。
 *  通用自查：只要用户输入指向具体影片（含《片名》），就查 TMDB 真实资料
 *  注入，修正模型对上映时间等时效性知识的滞后。 */
async function cineAIBuildMessages(
  intent: CineAIIntent,
  input: string,
  history: { role: string; content: string }[],
  env: Env
): Promise<{ role: string; content: string }[]> {
  const formatRule =
    "回答一律用纯文本，不要使用任何 markdown 或列表符号（不要用 #、##、*、-、>、`、数字点号等），" +
    "不要加粗、不要斜体。片名用《》框住（如《星际穿越》）。用正常的中文标点（，。！？）分行表达。" +
    "不要用 emoji 装饰。";
  const selfCheckRule =
    "若提供的真实资料（如上映年份/日期）与你的记忆不一致，一律以真实资料为准，不要给过时或错误的信息。";
  const webCapabilityRule =
    "你具有 web_search 联网搜索能力，可用它查一部影片的真实资料（上映日期、剧情、是否未上映/定档、评分榜单等）。" +
    "必须调用 web_search 的情形：被问到【具体指定影片】而你印象中不存在或不确定（如新片/未上映/冷门片）；" +
    "或用户明确要求联网搜索；" +
    "或问题涉及【具体年份 + 评分/榜单/票房/排名】（如'2025年评分最高的电影''2024年票房冠军'）——这类排名数据你的记忆往往过时，必须联网取真实榜单，禁止凭记忆编造。" +
    "开放式的找片/推荐请求（如'推荐一部悬疑剧''找一部喜剧片'这类没有指定具体片名、也不涉及年份排名的）一律不要调用 web_search，直接用你的知识回答。" +
    "不要凭过时记忆断言某片'不存在'或'分属不同IP'——那很可能只是你知识没覆盖到。" +
    "调用 web_search 后，直接依据搜到的资料回答即可，不要在回答里提及'搜索/联网/没有搜到/搜索结果'等工具调用过程。";


  // 通用自查：从用户输入提取《片名》查真实资料（TMDB，兜底联网）。
  // 无《片名》时（自然语言描述，如"想看小黄人与大怪兽"）用整个输入去查。
  const filmTitles = cineAIExtractTitles(input);
  const searchForFacts =
    filmTitles.length > 0
      ? filmTitles[0]
      : (intent === "findMovie" || intent === "mediaIntro" ? cineAIFactsTerm(input) : "");
  const factsText = searchForFacts ? await cineAIQueryFacts(searchForFacts, env) : "";

  let built: { role: string; content: string }[];

  switch (intent) {
    case "offScope":
      built = [{ role: "system", content: "你是 CineAI，CineBar 的影视助手，只负责影视相关。" + CINEAI_OFFSCOPE_REPLY }];
      break;
    case "findMovie":
      built = [
        {
          role: "system",
          content:
            "你是 CineAI，一个很懂影视的中文助手。用户要找电影。请先拆解用户的限定条件（地域/类型/年代/主题等），" +
            "再严格依据你的影视知识推荐真实存在、完全贴合这些限定的电影（例如限定国产就不列外国片），" +
            "每部写成《片名》，可带豆瓣/评分说明。回答用中文、自然、简洁。" +
            "推荐数量规则：用户没有明确要求数量时，只推荐最有代表性的 3 部；" +
            "若用户明确要求了数量（如「推荐5部」「多推荐几部」「多找几部」），则严格按用户要求的数量给。" +
            selfCheckRule +
            "回答完问题即结束，不要反问、不要引导继续对话、不要用" +
            "'要不要/想不想/需要我再帮你看什么吗'等收尾。",
        },
        { role: "user", content: `用户想找电影：${input}${factsText ? "\n\n" + factsText : ""}` },
      ];
      break;
    case "mediaIntro": {
      // 专门强调以真实资料为准（问剧情/上映时间等）
      const facts = factsText ||
        "（未检索到，请依据你的影视知识回答，但对上映时间等时效信息若不确定要如实说明，不要编造。）";
      built = [
        {
          role: "system",
          content:
            "你是 CineAI，一个很懂影视的中文助手。介绍这部作品时，请以提供的事实资料为准，" +
            "尤其是上映时间、年份等时效信息必须以资料为准，不要凭印象猜测或给过时答案。" +
            selfCheckRule +
            "对不确切的细节用词留有余地（如大致、我记得）。回答用中文、自然、简洁。" +
            "回答完即结束，不要反问、不要引导继续对话、不要以'要不要/想不想了解'等收尾。",
        },
        { role: "user", content: `用户问：${input}\n\n${facts}` },
      ];
      break;
    }
    case "recommend":
      built = [
        {
          role: "system",
          content:
            "你是 CineAI，一个很懂影视的中文助手，尤其熟悉中国观众的片单喜好。用户要电影推荐。" +
            "请先准确拆解用户的每一个限定条件（如地域「国产/港片/欧美/日韩」、类型、年代、主题等），" +
            "然后**严格依据你的影视知识**推荐完全贴合这些限定的电影。所有推荐必须同时满足用户的每个限定：" +
            "例如用户限定「国产」时，只能推荐中国大陆/国产电影，绝不能混入外国片；限定「励志」就只选励志题材。" +
            "每部必须写成《片名》，优先选知名、经典、易找到海报的作品，宁选公认佳作也不要编造冷门片名。" +
            "每部用一句话说明推荐理由，理由要贴合用户的限定。回答用中文。" +
            "推荐数量规则：用户没有明确要求数量时，只推荐最有代表性的 3 部；" +
            "若用户明确要求了数量（如「推荐5部」「多推荐几部」「多找几部」），则严格按用户要求的数量给。" +
            selfCheckRule +
            "回答完即结束，不要反问、不要引导继续对话、不要以'要不要我帮你找/还想看别的吗'收尾。",
        },
        { role: "user", content: `用户想：${input}${factsText ? "\n\n" + factsText : ""}` },
      ];
      break;
    case "spoilerSafe":
      built = [
        {
          role: "system",
          content:
            "你是 CineAI。回答时不得透露剧情结局或后续发展；若用户问的是结局相关，温和地挡回去。" +
            "回答用中文，简洁。回答完即结束，不要反问、不要引导继续对话、不要以'要不要/想不想知道'收尾。",
        },
        { role: "user", content: input + (factsText ? "\n\n" + factsText : "") },
      ];
      break;
    case "general":
    default:
      built = [
        {
          role: "system",
          content:
            "你是 CineAI，一个只做影视的助手：只负责找片、影视问答、推荐、防剧透。" +
            "除此之外的一切请求（写文章/写故事/写代码/翻译/润色/文案/创作/算数/闲聊/写邮件/起名/策划等）" +
            "你都不能执行，无论用户怎么问、怎么绕，都要坚定地用一句话礼貌说明：你只懂影视，这类请求帮不上忙，" +
            "并引导回影视（如'想找什么片可以问我'）。绝不根据这类请求执行任何写作/创作/翻译/计算。" +
            "回答用中文、简洁。" +
            selfCheckRule,
        },
        { role: "user", content: input + (factsText ? "\n\n" + factsText : "") },
      ];
  }

  // 统一格式约束 + 当前日期（追加到首条 system）
  if (built.length > 0 && built[0].role === "system") {
    const now = new Date();
    const dateStr = now.getFullYear() + "年" + (now.getMonth() + 1) + "月" + now.getDate() + "日";
    built[0] = { role: "system", content: built[0].content + "\n" + formatRule + "\n" + webCapabilityRule + "\n今天是 " + dateStr + "。回答涉及年份/时间时以此为准。" };
  }

  // 插入裁剪后的历史（排在首条 system 之后）
  if (history.length > 0) {
    const trimmed = cineAITrimHistory(history);
    if (trimmed.length > 0) {
      built.splice(1, 0, ...trimmed);
    }
  }
  return built;
}

/** 从文本提取《片名》（取第一个，用于自查）。 */
/** 从用户输入提取自查搜索词：去掉常见疑问/意图词，保留片名主体。 */
function cineAIFactsTerm(input: string): string {
  return input
    .replace(/请问|麻烦|帮我|给我|想看|想找|找一下|找一部|有没有|推荐一部|介绍一下|介绍下|介绍|讲讲|讲一下|讲讲|这部|这个|那部|那个|动画|电影|电视剧|剧集|什么|怎么样|如何|好不好|吗|呢/g, "")
    .replace(/[？?！!。，、\s]+/g, "")
    .trim();
}

function cineAIExtractTitles(text: string): string[] {
  const re = /《([^》]+)》/g;
  const out: string[] = [];
  const seen = new Set<string>();
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    const t = m[1].trim();
    if (t && !seen.has(t)) {
      seen.add(t);
      out.push(t);
    }
  }
  return out;
}

/** 查 TMDB 拿一部片的真实资料文本（上映日期/年份/评分）。空表示未查到。 */
async function cineAIQueryFacts(title: string, env: Env): Promise<string> {
  const info = await cineaiTMDBInfo(title, env);
  if (info.length > 0) {
    return "（自查到的真实资料）\n" + info.map((m) => {
      let line = `《${m.title}》（${m.mediaType === "tv" ? "剧集" : "电影"}）`;
      if (m.year) line += `，上映/首播日期 ${m.year}`;
      if (m.rating > 0) line += `，评分 ${m.rating.toFixed(1)}`;
      return line;
    }).join("\n");
  }
  // 库/影库查不到（新片、冷门）：联网搜索兜底，避免 AI 断言"不存在"
  const web = await cineWebSearch(title);
  if (web) return "（联网搜索到的资料）\n" + web;
  return "";
}

/** 联网搜索兜底：多搜索引擎逐源尝试，命中第一个能解析出结果的源。
 *  用于 TMDB/影库查不到的新片、冷门片，让 AI 基于真实信息回答而非断言不存在。
 *  不同搜索引擎在不同地域/反爬策略下可用性不同，故做逐源兜底。 */
async function cineWebSearch(query: string): Promise<string> {
  const q = query.trim().slice(0, 50);
  if (!q) return "";
  // 实测（CF 边缘）：百度可靠且返回正确中文结果；bing-www 能抓但中文查询会错配成无关英文结果；
  // bing-cn 被重定向到空结果页；sogou 触发反爬。故百度优先，必应仅作兜底。
  const sources: { name: string; url: string; parse: (html: string) => string }[] = [
    { name: "baidu", url: `https://www.baidu.com/s?wd=${encodeURIComponent(q)}`, parse: parseBaiduResults },
    { name: "bing-www", url: `https://www.bing.com/search?q=${encodeURIComponent(q)}&setlang=zh-hans&mkt=zh-CN`, parse: parseBingResults },
    { name: "bing-cn", url: `https://cn.bing.com/search?q=${encodeURIComponent(q)}`, parse: parseBingResults },
    { name: "sogou", url: `https://www.sogou.com/web?query=${encodeURIComponent(q)}`, parse: parseSogouResults },
  ];
  for (const s of sources) {
    const out = await cineSearchFetch(s.url, s.parse);
    if (out) return `（来源：${s.name}）\n` + out;
    // 百度偶发反爬验证（CF IP），重试一次以提高命中
    if (s.name === "baidu") {
      await new Promise((r) => setTimeout(r, 300));
      const retry = await cineSearchFetch(s.url, s.parse);
      if (retry) return `（来源：${s.name}）\n` + retry;
    }
  }
  return "";
}

/** 抓取单个搜索源并解析；失败/被拦/无结果都返回空串，交给下一源。 */
async function cineSearchFetch(url: string, parse: (html: string) => string): Promise<string> {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    const resp = await fetch(url, {
      redirect: "follow",
      headers: {
        "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36",
        accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
      },
      signal: controller.signal,
    });
    clearTimeout(timer);
    if (!resp.ok) return "";
    const html = await resp.text();
    return parse(html).slice(0, 600);
  } catch {
    return "";
  }
}

/** 解析必应（b_algo 结果块）标题+摘要。 */
function parseBingResults(html: string): string {
  const blocks = html.match(/<li class="b_algo"[\s\S]*?<\/li>/g) ?? [];
  const lines: string[] = [];
  for (const block of blocks.slice(0, 4)) {
    const titleMatch = block.match(/<h2[^>]*>\s*<a[^>]*>([\s\S]*?)<\/a>/);
    const title = titleMatch ? stripHTML(titleMatch[1]).trim() : "";
    const snipMatch = block.match(/<p[^>]*>([\s\S]*?)<\/p>/);
    const snippet = snipMatch ? stripHTML(snipMatch[1]).replace(/&#0*183;/g, "·").replace(/&ensp;/g, " ").trim() : "";
    const combined = [title, snippet].filter(Boolean).join("：");
    if (combined) lines.push(combined);
  }
  const out = lines.join("\n");
  // 中文查询时，若必应错配成纯英文无关结果（CF 边缘常见），视为无效返回空，
  // 避免把无关结果当成"真实资料"喂给 AI。
  return /[\u4e00-\u9fff]/.test(out) ? out : "";
}

/** 解析搜狗（vrwrap 结果块）标题+摘要。 */
function parseSogouResults(html: string): string {
  const blocks = html.match(/<div class="vrwrap"[\s\S]*?<\/div>\s*<\/div>/g) ?? [];
  const lines: string[] = [];
  for (const block of blocks.slice(0, 4)) {
    const titleMatch = block.match(/<h3[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/);
    const title = titleMatch ? stripHTML(titleMatch[1]).trim() : "";
    const snipMatch = block.match(/<div class="text-layout"[\s\S]*?>([\s\S]*?)<\/div>/);
    const snippet = snipMatch ? stripHTML(snipMatch[1]).trim() : "";
    const combined = [title, snippet].filter(Boolean).join("：");
    if (combined) lines.push(combined);
  }
  return lines.join("\n");
}

/** 解析百度（result c-container 结果块）标题+摘要。 */
function parseBaiduResults(html: string): string {
  // 取每个结果块：标题 <h3> 链接文本 + 摘要（c-abstract 或 content-right_* 容器）
  const blocks = html.split(/<div[^>]*class="[^"]*result c-container[^"]*"/).slice(1);
  const lines: string[] = [];
  for (const block of blocks.slice(0, 5)) {
    const titleMatch = block.match(/<h3[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/);
    const title = titleMatch ? stripHTML(titleMatch[1]).trim() : "";
    const snipMatch =
      block.match(/<div[^>]*class="c-abstract[^"]*"[\s\S]*?>([\s\S]*?)<\/div>/) ||
      block.match(/<span[^>]*class="content-right_[^"]*"[^>]*>([\s\S]*?)<\/span>/);
    const snippet = snipMatch ? stripHTML(snipMatch[1]).trim() : "";
    const combined = [title, snippet].filter(Boolean).join("：");
    if (combined) lines.push(combined);
  }
  return lines.join("\n");
}

function stripHTML(s: string): string {
  return String(s ?? "").replace(/<[^>]+>/g, "").replace(/&[a-z]+;/g, " ").trim();
}

/** 裁剪历史，避免请求体过大触发代理 413：最多最近 6 条、总字符 ≤3000、单条 ≤800。 */
function cineAITrimHistory(
  history: { role: string; content: string }[]
): { role: string; content: string }[] {
  const maxCount = 6;
  const totalBudget = 3000;
  const perMessageLimit = 800;
  const recent = history.slice(-maxCount);
  const kept: { role: string; content: string }[] = [];
  let used = 0;
  for (const msg of [...recent].reverse()) {
    let content = msg.content;
    if (content.length > perMessageLimit) {
      content = content.slice(0, perMessageLimit) + "…";
    }
    if (used + content.length > totalBudget && kept.length > 0) break;
    kept.push({ role: msg.role, content });
    used += content.length;
  }
  return kept.reverse();
}

async function handleCineAI(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "method not allowed" }),
      { status: 405, headers: { "content-type": "application/json; charset=utf-8" } }
    );
  }
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return new Response(
      JSON.stringify({ error: "bad request" }),
      { status: 400, headers: { "content-type": "application/json; charset=utf-8" } }
    );
  }
  const b = body as Record<string, unknown>;
  const device = normalizeText(b?.device as string | null | undefined).slice(0, 128);
  const rawMessages = Array.isArray(b?.messages) ? (b.messages as unknown[]) : [];
  const messages = rawMessages
    .filter((m) => m && typeof m === "object")
    .map((m) => {
      const o = m as Record<string, unknown>;
      return { role: String(o.role ?? "user"), content: String(o.content ?? "") };
    })
    .filter((m) => m.content.length > 0)
    .slice(0, CINEAI_MAX_MESSAGES);
  if (!device || messages.length === 0) {
    return new Response(
      JSON.stringify({ error: "device and messages are required" }),
      { status: 400, headers: { "content-type": "application/json; charset=utf-8" } }
    );
  }
  const totalChars = messages.reduce((s, m) => s + m.content.length, 0);
  if (totalChars > CINEAI_MAX_INPUT_CHARS) {
    return new Response(
      JSON.stringify({ error: "input too large" }),
      { status: 413, headers: { "content-type": "application/json; charset=utf-8" } }
    );
  }

  // 取最后一条用户消息做意图判断；历史 = 除最后一条外的全部消息
  const lastUser = [...messages].reverse().find((m) => m.role === "user");
  const lastInput = lastUser ? lastUser.content : "";
  const intent = cineAIIntent(lastInput);

  // offScope：本地硬拦截，不调模型、不耗 token
  if (intent === "offScope") {
    return new Response(
      JSON.stringify({ content: CINEAI_OFFSCOPE_REPLY, offScope: true }),
      { status: 200, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } }
    );
  }

  // 历史（排除最后一条，因最后一条已作为当前输入）
  const history = messages.slice(0, -1);
  const builtMessages = await cineAIBuildMessages(intent, lastInput, history, env);

  // 第一轮：带上 web_search 工具，让模型自主决定是否联网。
  const round1 = await cineCallProxy(device, builtMessages, env);
  if (!round1.ok) {
    return new Response(
      JSON.stringify({ error: round1.error ?? "unavailable", detail: round1.detail }),
      { status: round1.status, headers: { "content-type": "application/json; charset=utf-8" } }
    );
  }

  let firstMsg = round1.firstMessage as Record<string, unknown> | undefined;
  let usedWeb = false;
  let searchBudget = 3; // 单次请求最多执行的 web_search 次数，防止模型连环调用打爆成本
  const MAX_ROUNDS = 3; // 最多来回几轮（含第一轮）

  // 工具循环：模型只要返回 tool_calls 且还没到上限，就执行搜索回填，再发下一轮。
  // runningMessages 累计完整消息序列（system + user + assistant(tool_calls) + tool 结果），跨轮传递。
  let runningMessages: Record<string, unknown>[] = builtMessages;
  for (let round = 0; round < MAX_ROUNDS; round++) {
    const toolCalls = Array.isArray(firstMsg?.tool_calls) ? firstMsg.tool_calls : [];
    if (toolCalls.length === 0) break;

    const withTools = [...runningMessages];
    withTools.push(firstMsg as Record<string, unknown>);
    for (const call of toolCalls) {
      const fn = (call as Record<string, unknown>)?.function as Record<string, unknown> | undefined;
      if (fn?.name !== "web_search") continue;
      if (searchBudget <= 0) {
        withTools.push({
          role: "tool",
          tool_call_id: String((call as Record<string, unknown>)?.id ?? ""),
          content: "（已达到本次联网次数上限，请直接基于已有信息回答，不要再调用搜索。）",
        });
        continue;
      }
      searchBudget--;
      usedWeb = true;
      const args = (fn.arguments && typeof fn.arguments === "string" ? safeJSONParse(fn.arguments) : fn.arguments) as
        Record<string, unknown> | null | undefined;
      const query = String(args?.query ?? "").trim();
      const output = query ? await cineWebSearch(query) : "";
      // 工具结果中性化：去掉"（来源：baidu）"这类过程信息，避免模型泄露"联网/搜索"痕迹。
      const neutral = output.replace(/^（来源：[^）]+）\n?/, "").trim();
      withTools.push({
        role: "tool",
        tool_call_id: String((call as Record<string, unknown>)?.id ?? ""),
        content: neutral || "（未查到该片的确切资料，请如实说明信息有限，不要编造。）",
      });
    }
    runningMessages = withTools;
    const next = await cineCallProxy(device, withTools, env);
    if (!next.ok) {
      return new Response(
        JSON.stringify({ error: next.error ?? "unavailable", detail: next.detail }),
        { status: next.status, headers: { "content-type": "application/json; charset=utf-8" } }
      );
    }
    firstMsg = next.firstMessage as Record<string, unknown> | undefined;
  }

  // 兜底：模型多轮仍没产出文本（可能它最后一轮又在调工具/空 content），给一句友好提示，避免前端显示"（没有收到回复）"。
  const content = String(firstMsg?.content ?? "").trim();
  const finalAnswer = content
    ? content
    : "抱歉，我刚才没整理好答案。如果你问的是具体某部影片，可以告诉我片名，我再帮你查；如果是找片推荐，换个说法我再试试。";

  return new Response(
    JSON.stringify({
      content: finalAnswer,
      cached: false,
      usedWeb,
      ...(content ? {} : { fallback: true }),
    }),
    { status: 200, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } }
  );
}

/** 调用 CineAI 代理一次，返回 { ok, status, error, detail, result, firstMessage, cached }。 */
async function cineCallProxy(
  device: string,
  messages: Record<string, unknown>[],
  env: Env
): Promise<{
  ok: boolean;
  status: number;
  error?: string;
  detail?: unknown;
  result?: Record<string, unknown>;
  firstMessage?: unknown;
  cached?: boolean;
}> {
  let upstream: Response;
  try {
    upstream = await fetch(CINEAI_PROXY_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ device, messages, tools: CINEAI_WEB_TOOLS }),
    });
  } catch {
    return { ok: false, status: 502, error: "unavailable" };
  }
  let data: Record<string, unknown>;
  try {
    data = (await upstream.json()) as Record<string, unknown>;
  } catch {
    data = {};
  }
  if (upstream.status === 429) {
    return { ok: false, status: 429, error: "rate limited", detail: data?.error };
  }
  if (!upstream.ok) {
    return { ok: false, status: 502, error: "upstream error", detail: data?.error };
  }
  const result = data?.result as Record<string, unknown> | undefined;
  const choices = Array.isArray(result?.choices) ? result.choices : [];
  const first = choices[0] as Record<string, unknown> | undefined;
  return {
    ok: true,
    status: upstream.status,
    result,
    firstMessage: (first?.message as Record<string, unknown> | undefined) ?? undefined,
    cached: !!data?.cached,
  };
}

/** 安全解析 JSON 字符串，失败返回 null。 */
function safeJSONParse(s: string): unknown {
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}


/** Records a page view into the D1 stats database. IP is hashed one-way
 *  (SHA-256) so raw visitor addresses are never persisted. Fires in the
 *  background and never blocks or fails the response. */
async function recordPageVisit(request: Request, env: Env, url: URL): Promise<void> {
  try {
    const rawIp = request.headers.get("cf-connecting-ip") ?? "";
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`cinebar:${rawIp}`));
    const ipHash = Array.from(new Uint8Array(digest))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    const firstSegment = url.pathname.split("/").filter(Boolean)[0] ?? "";
    const locale = ["zh-Hans", "zh-Hant", "en", "ja", "ko"].includes(firstSegment)
      ? firstSegment
      : "zh-Hans";

    await env.DB.prepare(
      "INSERT INTO page_visits (ts, path, country, ip_hash, locale) VALUES (?, ?, ?, ?, ?)"
    )
      .bind(
        Math.floor(Date.now() / 1000),
        url.pathname,
        request.headers.get("cf-ipcountry") ?? "--",
        ipHash,
        locale,
      )
      .run();
  } catch {
    // Statistics must never break the page itself.
  }
}

/** A navigational page request worth counting: HTML document requests that
 *  are not admin pages, API endpoints, or static assets. */
function shouldRecordPageVisit(request: Request, url: URL): boolean {
  if (request.method !== "GET" && request.method !== "HEAD") return false;
  if (!isNavigationalRequest(request)) return false;
  if (url.pathname === "/admin/analytics") return false;
  if (url.pathname.startsWith("/api/")) return false;
  if (url.pathname.startsWith("/_vinext")) return false;
  if (/\.(css|js|png|jpe?g|svg|ico|webp|woff2?|json|zip|txt|xml|mp4|pdf)$/i.test(url.pathname)) return false;
  return true;
}

function isWeChatBrowser(request: Request): boolean {
  const ua = request.headers.get("user-agent") ?? "";
  return /MicroMessenger/i.test(ua);
}

function isNavigationalRequest(request: Request): boolean {
  const accept = request.headers.get("accept") ?? "";
  return /text\/html/i.test(accept);
}

function wechatGuideHtml(request: Request): Response {
  const continueUrl = new URL(request.url);
  continueUrl.searchParams.set("_wx_continue", "1");
  const page = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>请在浏览器中打开 — CineBar</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; margin: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    background: #0a0d1f;
    color: #f7f5f1;
    min-height: 100svh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 32px 20px;
  }
  .card { max-width: 420px; width: 100%; text-align: center; }
  .logo {
    width: 72px;
    height: 72px;
    border-radius: 18px;
    margin: 0 auto 24px;
    display: block;
    box-shadow: 0 12px 32px rgba(0,0,0,.4);
  }
  h1 { font-size: 1.5rem; font-weight: 800; letter-spacing: -.02em; margin-bottom: 12px; }
  p  { font-size: .95rem; line-height: 1.7; color: #b9bed1; margin-bottom: 18px; }
  .step {
    background: #151a33;
    border: 1px solid #242a4a;
    border-radius: 14px;
    padding: 16px;
    margin-bottom: 12px;
    text-align: left;
  }
  .step b { display: block; color: #fff; font-size: .95rem; margin-bottom: 4px; }
  .step span { font-size: .85rem; color: #b9bed1; }
  .btn {
    display: inline-block;
    margin-top: 10px;
    padding: 13px 26px;
    border-radius: 999px;
    background: #34d399;
    color: #06281c;
    font-size: .95rem;
    font-weight: 750;
    text-decoration: none;
  }
  .hint { margin-top: 18px; font-size: .78rem; color: #7a7ea0; }
</style>
</head>
<body>
  <div class="card">
    <img class="logo" src="/cinebar-icon.png" alt="" width="72" height="72" />
    <h1>请在浏览器中打开</h1>
    <p>微信内置浏览器对境外网站会有安全提示。为了更顺畅地浏览 CineBar 官网，请点击右上角「···」，选择<b>「在浏览器中打开」</b>。</p>
    <div class="step"><b>1</b><span>点击右上角「···」</span></div>
    <div class="step"><b>2</b><span>选择「在浏览器中打开」</span></div>
    <a class="btn" href="${continueUrl.toString()}">继续在微信内浏览</a>
    <p class="hint">官网部署在境外服务器，微信提示“未完成 ICP 备案”是正常现象，网站本身安全。</p>
  </div>
</body>
</html>`;
  return new Response(page, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function adminAnalyticsUnauthorized(url: URL): Response {
  const response = new Response("Administrator authentication required.", {
    status: 401,
    headers: {
      "cache-control": "no-store",
      "content-type": "text/plain; charset=utf-8",
      "www-authenticate": 'Basic realm="CineBar Analytics", charset="UTF-8"',
    },
  });
  return addSecurityHeaders(response, url);
}

type SiteStatsPayload = {
  total_views: number;
  unique_visitors: number;
  views_7d: number;
  by_path: { path: string; views: number }[];
  by_country: { country: string; views: number }[];
  by_day: { day: string; views: number }[];
  latest: { ts: string; path: string; country: string; locale: string }[];
};

/** 网页访问统计读取（在 Worker 层，env.DB 可直接用）。
 *  供 /api/admin/site-stats 使用，避免 Next SSR 读不到 D1 binding。 */
async function loadSiteStatsDB(env: Env): Promise<SiteStatsPayload | null> {
  try {
    const now = Math.floor(Date.now() / 1000);
    const weekAgo = now - 7 * 86400;

    const [total, unique, week, pathRows, countryRows, dayRows, latestRows] =
      await Promise.all([
        env.DB.prepare("SELECT COUNT(*) AS n FROM page_visits").first(),
        env.DB.prepare(
          "SELECT COUNT(DISTINCT ip_hash) AS n FROM page_visits"
        ).first(),
        env.DB.prepare(
          "SELECT COUNT(*) AS n FROM page_visits WHERE ts >= ?"
        ).bind(weekAgo).first(),
        env.DB.prepare(
          "SELECT path, COUNT(*) AS views FROM page_visits GROUP BY path ORDER BY views DESC LIMIT 10"
        ).all(),
        env.DB.prepare(
          "SELECT country, COUNT(*) AS views FROM page_visits GROUP BY country ORDER BY views DESC LIMIT 12"
        ).all(),
        env.DB.prepare(
          "SELECT strftime('%m-%d', ts, 'unixepoch') AS day, COUNT(*) AS views FROM page_visits GROUP BY day ORDER BY day DESC LIMIT 14"
        ).all(),
        env.DB.prepare(
          "SELECT ts, path, country, locale FROM page_visits ORDER BY id DESC LIMIT 12"
        ).all(),
      ]);

    return {
      total_views: Number(total?.n ?? 0),
      unique_visitors: Number(unique?.n ?? 0),
      views_7d: Number(week?.n ?? 0),
      by_path: (pathRows?.results ?? []).map((r) => ({
        path: String(r.path),
        views: Number(r.views),
      })),
      by_country: (countryRows?.results ?? []).map((r) => ({
        country: String(r.country),
        views: Number(r.views),
      })),
      by_day: (dayRows?.results ?? []).map((r) => ({
        day: String(r.day),
        views: Number(r.views),
      })),
      latest: (latestRows?.results ?? []).map((r) => ({
        ts: new Date(Number(r.ts) * 1000).toLocaleString("zh-CN", {
          hour12: false,
        }),
        path: String(r.path),
        country: String(r.country),
        locale: String(r.locale),
      })),
    };
  } catch {
    return null;
  }
}

function addSecurityHeaders(response: Response, url: URL): Response {
  const headers = new Headers(response.headers);
  headers.set("content-security-policy", CONTENT_SECURITY_POLICY);
  headers.set("permissions-policy", PERMISSIONS_POLICY);
  headers.set("referrer-policy", "strict-origin-when-cross-origin");
  headers.set("x-content-type-options", "nosniff");
  headers.set("x-frame-options", "DENY");
  if (url.protocol === "https:") {
    headers.set("strict-transport-security", HSTS_POLICY);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

// Image security config. SVG sources with .svg extension auto-skip the
// optimization endpoint on the client side (served directly, no proxy).
// To route SVGs through the optimizer (with security headers), set
// dangerouslyAllowSVG: true in next.config.js and uncomment below:
// const imageConfig: ImageConfig = { dangerouslyAllowSVG: true };

const worker = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (url.hostname === OFFICIAL_HOST && url.protocol === "http:") {
      url.protocol = "https:";
      return Response.redirect(url, 308);
    }

    // The telemetry API is protected, but the dashboard must be protected too.
    // Otherwise a guessed URL would reveal aggregate installation counts.
    if (url.pathname === "/admin/analytics" && !isAdminAnalyticsRequest(request, env)) {
      return adminAnalyticsUnauthorized(url);
    }

    // Worker 不能 fetch 回自己的域名，SSR 无法在 /admin/analytics 里自调用取 D1；
    // 这里鉴权通过后预先查好网页统计，经请求头注入给 SSR，再由页面用 headers() 读取。
    let adminRequest = request;
    if (url.pathname === "/admin/analytics") {
      const stats = await loadSiteStatsDB(env);
      const header = new Headers(request.headers);
      if (stats) header.set("x-cinebar-stats", JSON.stringify(stats));
      adminRequest = new Request(request, { headers: header });
    }

    if (shouldRecordPageVisit(request, url)) {
      ctx.waitUntil(recordPageVisit(request, env, url));
    }

    if (url.pathname === "/api/search" && request.method === "GET") {
      const response = await handleSearch(request, env);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/play" && request.method === "GET") {
      const response = await handlePlay(request, env);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/cms/search" && request.method === "GET") {
      const response = await handleCMSPlay(request, env);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/cms/list" && request.method === "GET") {
      const response = await handleCMSList(request);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/cms/detail" && request.method === "GET") {
      const response = await handleCMSDetail(request);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/cms/poster" && request.method === "GET") {
      const response = await handleCMSPoster(request);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/cms/stream" && request.method === "GET") {
      const response = await handleCMSStream(request);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/iptv" && request.method === "GET") {
      const response = await handleIPTV(request, env, ctx);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/iptv/stream" && request.method === "GET") {
      const response = await handleIPTVStream(request, env);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/iptv/logo" && request.method === "GET") {
      const response = await handleIPTVLogo(request);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/trending" && request.method === "GET") {
      const response = await handleTrending(request, env, ctx);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/nowplaying" && request.method === "GET") {
      const response = await handleNowPlaying(request, env);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/nowplaying-cn" && request.method === "GET") {
      const response = await handleNowPlayingCN(request);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/cineai" && request.method === "POST") {
      const response = await handleCineAI(request, env);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/lookup" && request.method === "GET") {
      const response = await handleLookup(request, env);
      return addSecurityHeaders(response, url);
    }

    if (request.method === "GET" || request.method === "HEAD") {
      const assetResponse = await env.ASSETS.fetch(request);
      if (assetResponse.status !== 404) {
        return addSecurityHeaders(assetResponse, url);
      }
    }

    if (isWeChatBrowser(request) && isNavigationalRequest(request)) {
      const params = url.searchParams;

      if (params.get("_wx_continue") !== "1") {
        return addSecurityHeaders(wechatGuideHtml(request), url);
      }
    }

    if (url.pathname === "/_vinext/image") {
      const allowedWidths = [...DEFAULT_DEVICE_SIZES, ...DEFAULT_IMAGE_SIZES];
      const response = await handleImageOptimization(request, {
        fetchAsset: (path) => env.ASSETS.fetch(new Request(new URL(path, request.url))),
        transformImage: async (body, { width, format, quality }) => {
          const result = await env.IMAGES.input(body).transform(width > 0 ? { width } : {}).output({ format, quality });
          return result.response();
        },
      }, allowedWidths);
      return addSecurityHeaders(response, url);
    }

    const response = await handler.fetch(adminRequest, env, ctx);
    return addSecurityHeaders(response, url);
  },
};

export default worker;
