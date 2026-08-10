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
const CONTENT_SECURITY_POLICY = "default-src 'self'; base-uri 'self'; form-action 'self' https://www.paypal.com; frame-ancestors 'none'; img-src 'self' data: blob: https://image.tmdb.org; object-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self' https://api.cinebar.cc https://share.cinebar.cc; font-src 'self' data:; upgrade-insecure-requests";
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
