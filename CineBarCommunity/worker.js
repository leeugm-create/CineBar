const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
      "access-control-allow-headers":
        "content-type, x-cinebar-key, x-cinebar-device",
      "access-control-allow-methods": "GET, POST, OPTIONS",
    },
  });

const normalizeText = (value) =>
  String(value ?? "")
    .replace(/\s+/g, " ")
    .trim();

const escapeHTML = (value) =>
  String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");

const sharePage = (url, movieID) => {
  const title = normalizeText(url.searchParams.get("title")).slice(0, 120) ||
    `电影 #${movieID}`;
  const year = normalizeText(url.searchParams.get("year")).slice(0, 12);
  const rating = normalizeText(url.searchParams.get("rating")).slice(0, 8);
  const summary = normalizeText(url.searchParams.get("summary")).slice(0, 240) ||
    "在 CineBar 发现这部电影。";
  const posterPath = normalizeText(url.searchParams.get("poster"));
  const safePoster = /^\/[A-Za-z0-9._/-]+$/.test(posterPath)
    ? `https://image.tmdb.org/t/p/w500${posterPath}`
    : "";
  const logoURL = `${url.origin}/cinebar-logo.svg`;
  const previewImage = safePoster || logoURL;
  const safeTitle = escapeHTML(title);
  const safeYear = escapeHTML(year);
  const safeRating = escapeHTML(rating);
  const safeSummary = escapeHTML(summary);
  const safePageURL = escapeHTML(url.href);

  const html = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${safeTitle} · CineBar</title>
  <meta name="description" content="${safeSummary}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="CineBar">
  <meta property="og:title" content="${safeTitle} · CineBar">
  <meta property="og:description" content="${safeSummary}">
  <meta property="og:image" content="${escapeHTML(previewImage)}">
  <meta property="og:url" content="${safePageURL}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${safeTitle} · CineBar">
  <meta name="twitter:description" content="${safeSummary}">
  <meta name="twitter:image" content="${escapeHTML(previewImage)}">
  <style>
    :root { color-scheme: dark; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
    * { box-sizing: border-box; }
    body {
      margin: 0; min-height: 100vh; color: #f8fafc;
      background:
        radial-gradient(circle at 80% 10%, rgba(245,158,11,.22), transparent 34rem),
        linear-gradient(145deg,#070a24,#11183f 55%,#080b22);
      display: grid; place-items: center; padding: 28px;
    }
    main { width: min(900px,100%); }
    header { display:flex; align-items:center; gap:14px; margin-bottom:24px; }
    .logo { width:62px; height:62px; border-radius:15px; box-shadow:0 12px 40px #0008; }
    .brand { font-size:30px; font-weight:800; letter-spacing:-.03em; }
    .tagline { color:#a9b4d0; margin-top:2px; }
    .card {
      display:grid; grid-template-columns:minmax(190px,290px) 1fr; gap:34px;
      padding:28px; border:1px solid #ffffff1f; border-radius:28px;
      background:#ffffff0d; backdrop-filter:blur(22px);
      box-shadow:0 28px 90px #0008;
    }
    .poster {
      width:100%; aspect-ratio:2/3; object-fit:cover; border-radius:18px;
      background:#ffffff0b; box-shadow:0 20px 50px #0009;
    }
    .empty-poster { display:grid; place-items:center; color:#8e9ab9; font-size:52px; }
    .content { align-self:center; }
    h1 { font-size:clamp(32px,6vw,60px); line-height:1.05; margin:0 0 14px; letter-spacing:-.045em; }
    .meta { display:flex; gap:10px; flex-wrap:wrap; margin-bottom:22px; }
    .pill { padding:7px 11px; border-radius:999px; background:#ffffff12; color:#d8def0; }
    .rating { background:#f59e0b22; color:#ffd36a; }
    p { color:#c2cae0; font-size:18px; line-height:1.7; margin:0; }
    .from { margin-top:30px; color:#7f8caf; font-size:14px; }
    @media (max-width:650px) {
      .card { grid-template-columns:1fr; padding:20px; }
      .poster { max-width:280px; margin:auto; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <img class="logo" src="${logoURL}" alt="CineBar Logo">
      <div><div class="brand">CineBar</div><div class="tagline">今晚看什么？</div></div>
    </header>
    <section class="card">
      ${safePoster
        ? `<img class="poster" src="${safePoster}" alt="${safeTitle} 海报">`
        : `<div class="poster empty-poster">▶</div>`}
      <div class="content">
        <h1>${safeTitle}</h1>
        <div class="meta">
          ${safeYear ? `<span class="pill">${safeYear}</span>` : ""}
          ${safeRating ? `<span class="pill rating">★ ${safeRating} / 10</span>` : ""}
        </div>
        <p>${safeSummary}</p>
        <div class="from">由 CineBar for macOS 分享</div>
      </div>
    </section>
  </main>
</body>
</html>`;

  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=3600",
      "x-content-type-options": "nosniff",
      "referrer-policy": "strict-origin-when-cross-origin",
    },
  });
};

const digest = async (value) => {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
};

const authorize = (request, env) => {
  if (!env.PUBLIC_KEY) return true;
  return request.headers.get("x-cinebar-key") === env.PUBLIC_KEY;
};

export const normalizeMediaType = (value) =>
  value === "movie" || value === "tv" ? value : null;

export const normalizeScore = (value) => {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  if (value < 0 || value > 10 || value * 2 !== Math.round(value * 2)) {
    return null;
  }
  return value;
};

export const ratingPath = (pathname) => {
  const match = pathname.match(/^\/v1\/(movie|tv)\/(\d+)\/rating$/);
  if (!match) return null;
  return { mediaType: match[1], mediaID: Number(match[2]) };
};

const deviceHashForRequest = async (request, env, required = true) => {
  const deviceID = normalizeText(request.headers.get("x-cinebar-device"));
  if (!deviceID) {
    if (required) throw new Error("缺少设备标识");
    return null;
  }
  if (deviceID.length > 160) throw new Error("无效的设备标识");
  return digest(`${env.DEVICE_SALT ?? "cinebar"}:${deviceID}`);
};

async function ratingSummary(request, mediaType, mediaID, env) {
  const deviceHash = await deviceHashForRequest(request, env, false);
  const summary = await env.DB.prepare(
    `SELECT ROUND(AVG(score), 1) AS average_score, COUNT(*) AS total
     FROM ratings WHERE media_type = ? AND media_id = ?`,
  )
    .bind(mediaType, mediaID)
    .first();

  let myScore = null;
  if (deviceHash) {
    const own = await env.DB.prepare(
      `SELECT score FROM ratings
       WHERE media_type = ? AND media_id = ? AND device_hash = ?`,
    )
      .bind(mediaType, mediaID, deviceHash)
      .first();
    myScore = own?.score == null ? null : Number(own.score);
  }

  return json({
    media_type: mediaType,
    media_id: mediaID,
    average_score:
      Number(summary?.total ?? 0) > 0
        ? Number(summary?.average_score ?? 0)
        : null,
    total: Number(summary?.total ?? 0),
    my_score: myScore,
  });
}

const alreadyRatedResponse = () =>
  json(
    {
      error: "这部影片已经评分，不能重复评分",
      code: "already_rated",
    },
    409,
  );

async function createRating(request, mediaType, mediaID, env) {
  const body = await request.json();
  const score = normalizeScore(body.score);
  if (score == null) {
    return json({ error: "评分须为 0–10，且以 0.5 为间隔" }, 400);
  }
  const deviceHash = await deviceHashForRequest(request, env);
  const existing = await env.DB.prepare(
    `SELECT score FROM ratings
     WHERE media_type = ? AND media_id = ? AND device_hash = ?`,
  )
    .bind(mediaType, mediaID, deviceHash)
    .first();
  if (existing?.score != null) return alreadyRatedResponse();

  const now = new Date().toISOString();
  try {
    await env.DB.prepare(
      `INSERT INTO ratings
         (media_type, media_id, device_hash, score, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
      .bind(mediaType, mediaID, deviceHash, score, now, now)
      .run();
  } catch (error) {
    if (`${error?.message ?? error}`.toUpperCase().includes("UNIQUE")) {
      return alreadyRatedResponse();
    }
    throw error;
  }

  return ratingSummary(request, mediaType, mediaID, env);
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return json({ ok: true });

    const url = new URL(request.url);
    const shareMatch = url.pathname.match(/^\/share\/movies\/(\d+)$/);
    if (shareMatch && request.method === "GET") {
      return sharePage(url, Number(shareMatch[1]));
    }

    if (!authorize(request, env)) return json({ error: "Unauthorized" }, 401);

    const rating = ratingPath(url.pathname);
    if (rating) {
      try {
        if (request.method === "GET") {
          return ratingSummary(
            request,
            rating.mediaType,
            rating.mediaID,
            env,
          );
        }
        if (request.method === "POST") {
          return createRating(
            request,
            rating.mediaType,
            rating.mediaID,
            env,
          );
        }
        if (request.method === "DELETE") {
          return json(
            { error: "评分提交后不可修改或删除" },
            405,
          );
        }
      } catch (error) {
        return json({ error: error?.message ?? "评分服务暂时不可用" }, 400);
      }
    }

    return json({ error: "Not found" }, 404);
  },
};
