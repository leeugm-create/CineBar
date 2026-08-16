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
  const params = new URLSearchParams({ kw: query });
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
};

/** 并发搜索全部 CMS 源，返回合并结果（每个源取前 6 条，总量封顶 30 条）。 */
async function cmsSearchAll(
  title: string,
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
      return data.list.slice(0, 6).map((v) => {
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
        };
      });
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

/** GET /api/cms/search?q=&episode= 返回苹果CMS 聚合搜索结果（含直链）。 */
async function handleCMSPlay(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const q = normalizeText(url.searchParams.get("q"));
  const episode = Number(url.searchParams.get("episode")) || 1;
  if (!q || q.length > 120) {
    return new Response(
      JSON.stringify({ error: "invalid q" }),
      { status: 400, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } }
    );
  }
  const titles = await cmsSearchAll(q);
  const results = titles.map((t) => ({
    source: t.source,
    sourceName: t.sourceName,
    id: t.id,
    title: t.title,
    year: t.year,
    poster: t.poster,
    category: t.category,
    episodeCount: t.episodeCount,
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


/** GET /api/trending 返回 moovie 每周热门电影与电视榜。
 *  type=all 时一次返回两榜（首页用）；type=movie 或 tv 时只返回单个榜。
 *  数据缓存在 D1，7 天有效，避免每次访问都抓取 moovie。 */
const TRENDING_CACHE_KEY = 1;
const TRENDING_CACHE_TTL_SECONDS = 7 * 24 * 60 * 60;

async function readTrendingCache(env: Env): Promise<{ movies: TrendingMovie[]; shows: TrendingMovie[] } | null> {
  try {
    const res = await env.DB.prepare(
      "SELECT data, updated_at FROM trending_cache WHERE id = ?"
    ).bind(TRENDING_CACHE_KEY).first<{ data: string; updated_at: number }>();
    if (!res?.data) return null;
    const now = Math.floor(Date.now() / 1000);
    if (now - Number(res.updated_at) > TRENDING_CACHE_TTL_SECONDS) return null;
    const parsed = JSON.parse(res.data);
    return {
      movies: Array.isArray(parsed.movies) ? parsed.movies : [],
      shows: Array.isArray(parsed.shows) ? parsed.shows : [],
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

/** ===== IPTV 电视直播（对标 zip0 的 /tv 板块） =====
 *  数据源：best-fan/iptv-sources（GitHub 开源，每日自动构建国内直播源）。
 *  GET /api/iptv 返回按分组组织的频道列表（央视/卫视/地方/其他）。
 *  结果缓存 6 小时（复用 trending_cache 表，id=2）。 */

const IPTV_SOURCES = [
  { id: "cn", name: "国内", url: "https://raw.githubusercontent.com/best-fan/iptv-sources/main/cn_all.m3u8" },
  { id: "cn-ghproxy", name: "国内(镜像)", url: "https://ghproxy.net/https://raw.githubusercontent.com/best-fan/iptv-sources/main/cn_all.m3u8" },
];

type IPTVChannel = {
  name: string;
  logo: string | null;
  url: string;
  group: string;
  responseTime: string;
};

const IPTV_CACHE_KEY = 2;
const IPTV_CACHE_TTL_SECONDS = 6 * 60 * 60;

async function readIPTVCache(env: Env): Promise<IPTVChannel[] | null> {
  try {
    const res = await env.DB.prepare(
      "SELECT data, updated_at FROM trending_cache WHERE id = ?"
    ).bind(IPTV_CACHE_KEY).first<{ data: string; updated_at: number }>();
    if (!res?.data) return null;
    const now = Math.floor(Date.now() / 1000);
    if (now - Number(res.updated_at) > IPTV_CACHE_TTL_SECONDS) return null;
    const parsed = JSON.parse(res.data);
    return Array.isArray(parsed) ? (parsed as IPTVChannel[]) : null;
  } catch {
    return null;
  }
}

async function writeIPTVCache(env: Env, channels: IPTVChannel[]): Promise<void> {
  try {
    await env.DB.prepare(
      "INSERT INTO trending_cache (id, data, updated_at) VALUES (?, ?, ?) " +
      "ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at"
    ).bind(IPTV_CACHE_KEY, JSON.stringify(channels), Math.floor(Date.now() / 1000)).run();
  } catch {
    // 缓存写入失败不阻塞响应
  }
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

/** GET /api/iptv 返回分组频道列表。 */
async function handleIPTV(request: Request, env: Env): Promise<Response> {
  let channels = await readIPTVCache(env);
  if (!channels) {
    const all: IPTVChannel[] = [];
    for (const src of IPTV_SOURCES) {
      try {
        const resp = await fetch(src.url, {
          headers: { "user-agent": "Mozilla/5.0" },
        });
        if (resp.ok) {
          const text = await resp.text();
          all.push(...parseIPVPlaylist(text));
        }
      } catch {
        // 单源失败不阻塞
      }
    }
    channels = all;
    if (channels.length > 0) {
      await writeIPTVCache(env, channels);
    }
  }
  // 按分组聚合并保留原始顺序。
  const groups: { name: string; channels: IPTVChannel[] }[] = [];
  const seen = new Map<string, number>();
  for (const ch of channels) {
    const g = ch.group || "其他";
    if (!seen.has(g)) {
      seen.set(g, groups.length);
      groups.push({ name: g, channels: [] });
    }
    groups[seen.get(g)!].channels.push(ch);
  }
  return new Response(
    JSON.stringify({ groups, total: channels.length, updatedAt: Date.now() }),
    {
      status: 200,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=600" },
    }
  );
}

async function handleTrending(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const type = normalizeText(url.searchParams.get("type")) || "all";
  const wantMovie = type === "all" || type === "movie";
  const wantTV = type === "all" || type === "tv";

  const cached = await readTrendingCache(env);
  const payload: Record<string, TrendingMovie[]> = {};

  if (cached && (cached.movies.length > 0 || cached.shows.length > 0)) {
    if (wantMovie) payload.movies = cached.movies;
    if (wantTV) payload.shows = cached.shows;
    return new Response(
      JSON.stringify(payload),
      { status: 200, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=3600" } }
    );
  }

  const [movieHtml, tvHtml] = await Promise.all([
    moovieFetch("/discover/movie"),
    moovieFetch("/discover/tv"),
  ]);

  const movies = movieHtml ? parseTrendingMovies(movieHtml) : [];
  const shows = tvHtml ? parseTrendingMovies(tvHtml) : [];

  if (!movieHtml && !tvHtml) {
    return new Response(
      JSON.stringify({ error: "trending unavailable" }),
      { status: 502, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } }
    );
  }

  // 为每部片补齐 tmdbId/type，供前端跳自家详情页。
  // 先用 Moovie 搜索拿该片年份（区分同名不同年份），再据此精确匹配 TMDB。
  // 只补前 10 部（覆盖首页展示）用并行，控请求量与限流。
  async function enrich(list: TrendingMovie[]) {
    await Promise.all(list.slice(0, 10).map(async (item) => {
      // 1) Moovie 搜索该片名，找 doubanID 匹配的卡片，取其年份
      let moovieYear = "";
      try {
        const params = new URLSearchParams({ kw: item.title });
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
      // 2) TMDB 匹配（带年份优先）
      const info = await cineaiTMDBInfo(item.title, env, moovieYear);
      if (info.length > 0 && info[0].tmdbId) {
        item.tmdbId = info[0].tmdbId;
        item.type = info[0].mediaType;
      }
    }));
  }
  await Promise.all([enrich(movies), enrich(shows)]);

  await writeTrendingCache(env, movies, shows);
  if (wantMovie) payload.movies = movies;
  if (wantTV) payload.shows = shows;
  return new Response(
    JSON.stringify(payload),
    { status: 200, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=3600" } }
  );
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
      const params = new URLSearchParams({ kw: zhName });
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

    if (url.pathname === "/api/iptv" && request.method === "GET") {
      const response = await handleIPTV(request, env);
      return addSecurityHeaders(response, url);
    }

    if (url.pathname === "/api/trending" && request.method === "GET") {
      const response = await handleTrending(request, env);
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
