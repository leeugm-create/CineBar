// CineAI 服务端代理（Cloudflare Worker + D1）
//
// 职责：
//  1. 保管 DeepSeek API Key —— 只有本代理拿到 key，客户端永远接触不到。
//  2. 仅开放一个端点 POST /v1/chat/completions。
//  3. 设备匿名 ID + 双限额（每日次数 + 每日 token），防刷、防一次超长把成本打爆。
//  4. 两层缓存：第一层精确缓存（V1 落地，跨用户共享）；第二层语义缓存（V1 预留）。
//  5. 记录用量与成本归因（按设备匿名 ID）。
//
// 客户端只需带 messages + 匿名 device，不携带任何模型 key。

// 单次输出上限：防止一次性超长上下文/输出把 token 预算打爆。
const MAX_OUTPUT_TOKENS = 900;
// 单次请求输入上限（粗略：字符量 → token 近似）。
const MAX_INPUT_CHARS = 8000;
// 每日限额默认（可配置）。
const DAILY_CALLS_LIMIT = 60;
const DAILY_TOKENS_LIMIT = 300_000;

const DEEPSEEK_BASE = "https://api.deepseek.com/v1/chat/completions";

// ---------- 工具 ----------

function json(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function dayKey(now = Date.now()) {
  return new Date(now).toISOString().slice(0, 10);
}

// 精确缓存 key：对消息做规范化哈希（去 device/时间戳等易变字段）。
async function exactKey(messages) {
  const payload = JSON.stringify({ messages });
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(payload));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function estimateInputTokens(chatText) {
  // 粗略估算：约每 1.6 字符折 1 token（中文偏保守），够做预算预检即可。
  return Math.ceil(chatText.length / 1.6);
}

// ---------- 主入口 ----------

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname !== "/v1/chat/completions" || request.method !== "POST") {
      return json({ error: "not found" }, 404);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "bad request" }, 400);
    }

    const device = String(body?.device ?? "").trim().slice(0, 128);
    const messages = Array.isArray(body?.messages) ? body.messages : null;
    if (!device || messages === null || messages.length === 0) {
      return json({ error: "device and messages are required" }, 400);
    }
    // 防注入：只允许 {role, content}；content 转字符串
    const clean = messages
      .filter((m) => m && typeof m === "object")
      .map((m) => ({
        role: String(m.role ?? "user"),
        content: String(m.content ?? ""),
      }))
      .filter((m) => m.content.length > 0);
    if (clean.length === 0) {
      return json({ error: "empty messages" }, 400);
    }
    const totalChars = clean.reduce((s, m) => s + m.content.length, 0);
    if (totalChars > MAX_INPUT_CHARS) {
      return json({ error: "input too large" }, 413);
    }

    const day = dayKey();
    const db = env.DB;
    if (!db) return json({ error: "db unavailable" }, 503);

    // ---------- 第一层：精确缓存（跨用户共享） ----------
    const cacheKey = await exactKey(clean);
    const cached = await db.prepare(
      "SELECT body FROM rsp_cache WHERE hash = ?"
    ).bind(cacheKey).first();
    if (cached) {
      return json({ cached: true, result: JSON.parse(cached.body) });
    }

    // ---------- 限额预检（次数 + token 双限制） ----------
    const usage = await db.prepare(
      "SELECT calls, tokens FROM usage WHERE device = ? AND day = ?"
    ).bind(device, day).first();
    const calls = usage?.calls ?? 0;
    const tokens = usage?.tokens ?? 0;
    if (calls >= DAILY_CALLS_LIMIT) {
      return json({ error: "今日调用次数已达上限，请明天再试" }, 429);
    }
    const estimated = estimateInputTokens(clean.map((m) => m.content).join("")) + MAX_OUTPUT_TOKENS;
    if (tokens + estimated > DAILY_TOKENS_LIMIT) {
      return json({ error: "今日用量已达上限" }, 429);
    }

    // ---------- 转发 DeepSeek（key 只在服务端） ----------
    const key = env.DEEPSEEK_API_KEY;
    if (!key) return json({ error: "server not configured" }, 503);

    let upstream;
    try {
      const resp = await fetch(DEEPSEEK_BASE, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${key}`,
        },
        body: JSON.stringify({
          model: body?.model ?? "deepseek-chat",
          messages: clean,
          max_tokens: MAX_OUTPUT_TOKENS,
        }),
      });
      upstream = await resp.json();
      if (!resp.ok) {
        return json({ error: "upstream error", detail: upstream }, 502);
      }
    } catch {
      return json({ error: "upstream unavailable" }, 502);
    }

    // ---------- 记录用量 + 写精确缓存 ----------
    const usageTokens = 0; // DeepSeek 未返回 usage 时保守为 0，避免错误累加爆预算
    // 若 upstream 带 usage 则用实际值。
    const inputT = upstream?.usage?.prompt_tokens ?? estimated;
    const outputT = upstream?.usage?.completion_tokens ?? 0;
    const totalSpent = inputT + outputT;
    await db.prepare(
      "INSERT INTO usage (device, day, calls, tokens) VALUES (?, ?, 1, ?) " +
      "ON CONFLICT(device, day) DO UPDATE SET calls = calls + 1, tokens = tokens + ?"
    ).bind(device, day, totalSpent, totalSpent).run();
    await db.prepare(
      "INSERT INTO rsp_cache (hash, body, at) VALUES (?, ?, ?) " +
      "ON CONFLICT(hash) DO NOTHING"
    ).bind(cacheKey, JSON.stringify(upstream), Date.now()).run();

    return json({ cached: false, result: upstream });
  },
};
