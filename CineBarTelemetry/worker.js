const VERSION = "0.8.3-test.10";
const MAX_BODY_BYTES = 8 * 1024;
const ALLOWED_FIELDS = new Set([
  "install_id",
  "app_version",
  "build",
  "platform",
  "os_major",
  "architecture",
  "language",
  "occurred_at",
]);
const LANGUAGES = new Set(["zh-Hans", "zh-Hant", "en", "ja", "ko"]);
const ARCHITECTURES = new Set(["arm64", "x86_64"]);

const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status,
  headers: {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    "access-control-allow-headers": "content-type, authorization",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "x-content-type-options": "nosniff",
  },
});

const text = (value) => typeof value === "string" ? value : "";

export const hashInstallID = async (installID, secret) => {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(installID),
  );
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
};

export const validateInstallPayload = (payload) => {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return "payload must be an object";
  }
  for (const key of Object.keys(payload)) {
    if (!ALLOWED_FIELDS.has(key)) return `unknown field: ${key}`;
  }
  if (!/^\w{8}-\w{4}-[1-5]\w{3}-[89abAB]\w{3}-\w{12}$/.test(
    text(payload.install_id),
  )) return "install_id is invalid";
  if (!/^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$/.test(
    text(payload.app_version),
  )) return "app_version is invalid";
  if (!Number.isInteger(payload.build) || payload.build < 1 || payload.build > 100000) {
    return "build is invalid";
  }
  if (payload.platform !== "macOS") return "platform is invalid";
  if (!Number.isInteger(payload.os_major) || payload.os_major < 10 || payload.os_major > 99) {
    return "os_major is invalid";
  }
  if (!ARCHITECTURES.has(payload.architecture)) return "architecture is invalid";
  if (!LANGUAGES.has(payload.language)) return "language is invalid";
  if (typeof payload.occurred_at !== "string" ||
      !Number.isFinite(Date.parse(payload.occurred_at))) {
    return "occurred_at is invalid";
  }
  return null;
};

const readJSON = async (request) => {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > MAX_BODY_BYTES) throw new Error("payload too large");
  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
    throw new Error("payload too large");
  }
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error("invalid JSON");
  }
};

const health = () => json({
  ok: true,
  service: "cinebar-telemetry",
  version: VERSION,
  utc: new Date().toISOString(),
});

const installReport = async (request, env) => {
  let payload;
  try {
    payload = await readJSON(request);
  } catch (error) {
    return json({ error: error.message }, 400);
  }
  const validationError = validateInstallPayload(payload);
  if (validationError) return json({ error: validationError }, 400);
  if (!env.DB || typeof env.DB.prepare !== "function") {
    return json({ error: "telemetry database is not configured" }, 503);
  }
  const secret = text(env.TELEMETRY_HMAC_SECRET);
  if (!secret) return json({ error: "telemetry is not configured" }, 503);
  const installHash = await hashInstallID(payload.install_id, secret);
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO installs
      (install_hash, first_seen_at, last_seen_at, app_version, build, platform,
       os_major, architecture, language)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(install_hash) DO UPDATE SET
       last_seen_at = excluded.last_seen_at,
       app_version = excluded.app_version,
       build = excluded.build,
       platform = excluded.platform,
       os_major = excluded.os_major,
       architecture = excluded.architecture,
       language = excluded.language`,
  ).bind(
    installHash,
    now,
    now,
    payload.app_version,
    payload.build,
    payload.platform,
    payload.os_major,
    payload.architecture,
    payload.language,
  ).run();
  return json({ accepted: true }, 202);
};

const adminAuthorized = (request, env) => {
  const token = text(env.TELEMETRY_ADMIN_TOKEN);
  return Boolean(token) && request.headers.get("authorization") === `Bearer ${token}`;
};

const summaryRows = async (db, column) => {
  const result = await db.prepare(
    `SELECT ${column}, COUNT(*) AS installs FROM installs GROUP BY ${column}`,
  ).all();
  return (result.results ?? []).map((row) => ({
    value: row.value ?? row[column],
    installs: Number(row.installs ?? 0),
  })).sort((left, right) => right.installs - left.installs);
};

const summary = async (request, env) => {
  if (!adminAuthorized(request, env)) return json({ error: "Unauthorized" }, 401);
  if (!env.DB || typeof env.DB.prepare !== "function") {
    return json({ error: "telemetry database is not configured" }, 503);
  }
  const url = new URL(request.url);
  const range = url.searchParams.get("range") ?? "30d";
  const rangeDays = { "7d": 7, "30d": 30, "90d": 90 }[range];
  if (!rangeDays) return json({ error: "range must be 7d, 30d, or 90d" }, 400);
  const now = new Date();
  const cutoff = new Date(now.getTime() - rangeDays * 86400000).toISOString();
  const activeCutoff = new Date(now.getTime() - 86400000).toISOString();
  const totalRow = await env.DB.prepare(
    "SELECT COUNT(*) AS total_installs FROM installs",
  ).first();
  const activeRow = await env.DB.prepare(
    "SELECT COUNT(*) AS active_installs FROM installs WHERE last_seen_at >= ?",
  ).bind(activeCutoff).first();
  return json({
    ok: true,
    range,
    since: cutoff,
    as_of: now.toISOString(),
    total_installs: Number(totalRow?.total_installs ?? 0),
    active_installs: Number(activeRow?.active_installs ?? 0),
    by_version: await summaryRows(env.DB, "app_version"),
    by_os_major: await summaryRows(env.DB, "os_major"),
    by_architecture: await summaryRows(env.DB, "architecture"),
    by_language: await summaryRows(env.DB, "language"),
  });
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return json({ ok: true }, 204);
    if (request.method === "GET" && url.pathname === "/health") return health();
    if (request.method === "POST" && url.pathname === "/v1/telemetry/install") {
      try {
        return await installReport(request, env);
      } catch {
        return json({ error: "telemetry write failed" }, 503);
      }
    }
    if (request.method === "GET" && url.pathname === "/v1/telemetry/summary") {
      try {
        return await summary(request, env);
      } catch {
        return json({ error: "telemetry summary failed" }, 503);
      }
    }
    return json({ error: "Not found" }, 404);
  },
};
