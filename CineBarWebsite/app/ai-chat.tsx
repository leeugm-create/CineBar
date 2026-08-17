"use client";

import { useEffect, useRef, useState } from "react";

type Message = { role: "user" | "assistant"; content: string; typing?: boolean; ts?: number };

type LookupResult = {
  found: boolean;
  type?: "movie" | "tv";
  id?: number;
  title?: string;
  year?: string;
  poster?: string | null;
  playable?: boolean;
  playPath?: string;
};

const DEVICE_KEY = "cineai.web.device";
const FONT_KEY = "cineai.web.fontStep";
// 字号步进：-1（比默认小1号）~ +4（比默认大4号），默认 0。实际字号 = 0.95 + 0.1*step rem。
const FONT_MIN = -1;
const FONT_MAX = 4;
const BASE_FONT_REM = 0.95;

function bubbleFontRem(step: number): number {
  return Math.round((BASE_FONT_REM + 0.1 * step) * 100) / 100;
}

function loadFontStep(): number {
  try {
    const n = Number(window.localStorage.getItem(FONT_KEY));
    if (Number.isFinite(n)) return Math.min(FONT_MAX, Math.max(FONT_MIN, Math.round(n)));
  } catch { /* ignore */ }
  return 0;
}

/** 格式化为 HH:mm（与 App 端一致）。 */
function formatTime(ts: number): string {
  const d = new Date(ts);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

function getDevice(): string {
  try {
    let d = window.localStorage.getItem(DEVICE_KEY);
    if (!d) {
      d = "web-" + Math.random().toString(36).slice(2, 10) +
        "-" + Date.now().toString(36);
      window.localStorage.setItem(DEVICE_KEY, d);
    }
    return d;
  } catch {
    return "web-" + Math.random().toString(36).slice(2, 10);
  }
}

const suggestions = [
  "推荐几部高分科幻电影",
  "《星际穿越》讲的是什么",
  "找一部轻松喜剧",
  "帮我找一部悬疑剧",
];

/** 从文本提取《片名》+ 关联集数/年份，最多 limit 个，去重保持顺序。 */
function extractTitles(text: string, limit = 5): { title: string; episode?: number; year?: string }[] {
  const re = /《([^》]+)》/g;
  const out: { title: string; episode?: number; year?: string }[] = [];
  const seen = new Set<string>();
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    const t = m[1].trim();
    if (!t || seen.has(t)) continue;
    seen.add(t);
    // 从《片名》之后到句末（。！？；换行）前，找集数与年份
    const rest = text.slice(m.index + m[0].length);
    const sentEnd = rest.search(/[。！？；\n]/);
    const tail = sentEnd === -1 ? rest : rest.slice(0, sentEnd);
    const item: { title: string; episode?: number; year?: string } = { title: t };
    const epMatch = tail.match(/第\s*(\d+)\s*(?:集|话|期)/);
    if (epMatch) item.episode = parseInt(epMatch[1], 10);
    // 年份：《片名》（2026）或 2026年 或 2026 紧邻片名
    const yearMatch = tail.match(/(19|20)\d{2}/);
    if (yearMatch) item.year = yearMatch[1];
    out.push(item);
    if (out.length >= limit) break;
  }
  return out;
}

/** 单条片名的海报小卡（独立 fetch lookup）。episode/year 可选（CINEAI 联动精确定位）。 */
function PosterCard({ title, episode, year }: { title: string; episode?: number; year?: string }) {
  const [data, setData] = useState<LookupResult | null>(null);

  useEffect(() => {
    let alive = true;
    const params = new URLSearchParams({ title });
    if (year) params.set("year", year);
    fetch(`/api/lookup?${params.toString()}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((body: LookupResult | null) => {
        if (alive && body && body.found) setData(body);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [title, year]);

  if (data === null) {
    return <span className="ai-poster-card ai-poster-loading" aria-hidden="true" />;
  }
  if (!data.found || data.id == null) return null;
  // 一律跳新播放页 /watch?title=（CineCMS 聚合搜索 + zip0 布局，2026-08-18 改：
  // 原跳 share.cinebar.cc 老分享页，用户要求片单点进即新播放页）。
  // 电视剧且 CINEAI 提到了具体集数 → 带 episode 参数直接定位该集
  const ep = data.type === "tv" && episode ? `&episode=${episode}` : "";
  const href = `/watch?title=${encodeURIComponent(data.title ?? title)}${ep}`;
  return (
    <a className={`ai-poster-card${data.playable ? " ai-poster-playable" : ""}`} href={href} target="_blank" rel="noreferrer">
      <span className="ai-poster-wrap">
        {data.poster ? (
          <img className="ai-poster-img" src={data.poster} alt={data.title ?? title} loading="lazy" />
        ) : (
          <span className="ai-poster-img ai-poster-empty">{String(data.title ?? title).slice(0, 2)}</span>
        )}
        {data.playable && <span className="ai-poster-badge">可看</span>}
      </span>
      <span className="ai-poster-title">{data.title ?? title}</span>
    </a>
  );
}

/** assistant 消息底部：解析《片名》渲染横排海报小卡。可看的排前面。 */
function AIPosterStrip({ text }: { text: string }) {
  const titles = extractTitles(text);
  if (titles.length === 0) return null;
  return (
    <div className="ai-poster-strip">
      {titles.map((item) => (
        <PosterCard key={item.title} title={item.title} episode={item.episode} year={item.year} />
      ))}
    </div>
  );
}

export default function AIChat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  // 打字机：正在打字的那条 assistant 消息已显示到的字符数
  const [typingLen, setTypingLen] = useState(0);
  const [fontStep, setFontStep] = useState<number>(0);
  const typingTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  const listRef = useRef<HTMLDivElement>(null);

  // 载入字号偏好
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- 本地偏好一次性回放
    setFontStep(loadFontStep());
  }, []);

  function changeFont(delta: number) {
    setFontStep((prev) => {
      const next = Math.min(FONT_MAX, Math.max(FONT_MIN, prev + delta));
      try {
        window.localStorage.setItem(FONT_KEY, String(next));
      } catch { /* ignore */ }
      return next;
    });
  }

  // 正在打字的 assistant 消息下标（通常是最后一条）
  const typingIndex = messages.reduce((acc, m, i) => (m.role === "assistant" && m.typing ? i : acc), -1);

  function stopTyping() {
    if (typingTimer.current) {
      clearInterval(typingTimer.current);
      typingTimer.current = null;
    }
  }

  useEffect(() => () => stopTyping(), []);

  // 历史会话过期时长：超过则不回放，避免旧代码时代的"不存在"等过时结论被当新结论展示。
  const SESSION_TTL_MS = 24 * 60 * 60 * 1000;

  useEffect(() => {
    try {
      const saved = window.localStorage.getItem("cineai.web.messages");
      if (!saved) return;
      const parsed = JSON.parse(saved) as unknown;
      // 新格式：{ at, messages }；旧格式：Message[]（无时间戳，视为已过期不回放）
      const list: Message[] = Array.isArray(parsed)
        ? []
        : Array.isArray((parsed as { messages?: unknown }).messages)
          ? (parsed as { messages: Message[] }).messages
          : [];
      const at = Array.isArray(parsed) ? 0 : Number((parsed as { at?: unknown }).at ?? 0);
      if (list.length === 0 || Date.now() - at > SESSION_TTL_MS) return;
      // eslint-disable-next-line react-hooks/set-state-in-effect -- 会话回放
      setMessages(list.slice(-20).map((m) => ({ ...m, typing: false })));
    } catch {
      /* ignore */
    }
  }, []);

  useEffect(() => {
    try {
      window.localStorage.setItem(
        "cineai.web.messages",
        JSON.stringify({ at: Date.now(), messages: messages.map(({ role, content, ts }) => ({ role, content, ts })).slice(-20) })
      );
    } catch {
      /* ignore */
    }
  }, [messages]);

  function clearChat() {
    setMessages([]);
    setInput("");
    setError("");
    try {
      window.localStorage.removeItem("cineai.web.messages");
    } catch {
      /* ignore */
    }
  }

  useEffect(() => {
    const el = listRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [messages, typingLen, busy]);

  // 打字机驱动
  useEffect(() => {
    const idx = typingIndex;
    if (idx < 0) return;
    const full = messages[idx].content;
    if (typingLen >= full.length) {
      stopTyping();
      // eslint-disable-next-line react-hooks/set-state-in-effect -- 打字结束收尾
      setMessages((prev) => prev.map((m, i) => (i === idx ? { ...m, typing: false } : m)));
      return;
    }
    typingTimer.current = setInterval(() => {
      setTypingLen((n) => {
        const next = Math.min(n + 1, full.length);
        if (next >= full.length) {
          stopTyping();
          setMessages((prev) => prev.map((m, i) => (i === idx ? { ...m, typing: false } : m)));
        }
        return next;
      });
    }, 28);
    return () => stopTyping();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [typingIndex]);

  async function ask(text: string) {
    const q = text.trim();
    if (!q || busy) return;
    // eslint-disable-next-line react-hooks/purity -- 事件处理器内取时间戳
    const now = Date.now();
    const userMsg: Message = { role: "user", content: q, typing: false, ts: now };
    const next = [...messages, userMsg];
    setMessages(next);
    setInput("");
    setError("");
    setBusy(true);
    const device = getDevice();
    try {
      const resp = await fetch("/api/cineai", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ device, messages: next.map(({ role, content }) => ({ role, content })) }),
      });
      const body = (await resp.json()) as { content?: string; error?: string; detail?: unknown };
      if (!resp.ok || body.error) {
        const msg = body.error === "rate limited"
          ? "今日对话次数已达上限，明天再来吧。"
          : body.error === "input too large"
            ? "问题太长啦，精简一下再试。"
            : "AI 暂时没响应，请稍后重试。";
        setError(msg);
        setMessages((prev) => [...prev, { role: "assistant", content: msg, typing: false, ts: Date.now() }]);
      } else {
        const reply = (body.content ?? "").trim() || "（没有收到回复）";
        setMessages((prev) => [...prev, { role: "assistant", content: reply, typing: true, ts: Date.now() }]);
        setTypingLen(0);
      }
    } catch {
      setError("网络异常，请检查后重试。");
      setMessages((prev) => [...prev, { role: "assistant", content: "网络异常，请检查后重试。", typing: false, ts: Date.now() }]);
    } finally {
      setBusy(false);
    }
  }

  function visible(m: Message, idx: number): string {
    if (idx === typingIndex) {
      return m.content.slice(0, typingLen);
    }
    return m.content;
  }

  return (
    <div className="ai-chat">
      {messages.length > 0 && (
        <div className="ai-chat-toolbar">
          <div className="ai-font-controls" role="group" aria-label="调整对话字号">
            <button type="button" className="ai-font-btn" onClick={() => changeFont(1)} disabled={fontStep >= FONT_MAX} aria-label="增大字号">A+</button>
            <button type="button" className="ai-font-btn" onClick={() => changeFont(-1)} disabled={fontStep <= FONT_MIN} aria-label="减小字号">A−</button>
          </div>
          <button type="button" className="ai-clear-btn" onClick={clearChat} disabled={busy}>
            清空对话
          </button>
        </div>
      )}
      <div className="ai-chat-list" ref={listRef}>
        {messages.length === 0 ? (
          <div className="ai-chat-empty">
            <p>我是 CineAI，CineBar 里的影视助手。</p>
            <p>可以问我：找片、问剧情、求推荐、防剧透问答。</p>
            <div className="ai-suggestions">
              {suggestions.map((s) => (
                <button key={s} type="button" onClick={() => ask(s)}>
                  {s}
                </button>
              ))}
            </div>
          </div>
        ) : (
          messages.map((m, i) => (
            <div key={i} className={`ai-bubble ${m.role}`}>
              <div className="ai-bubble-content" style={{ fontSize: `${bubbleFontRem(fontStep)}rem` }}>{visible(m, i)}</div>
              {m.role === "assistant" && typingIndex !== i ? (
                <AIPosterStrip text={m.content} />
              ) : null}
              {m.ts ? <span className="ai-bubble-time">{formatTime(m.ts)}</span> : null}
            </div>
          ))
        )}
        {busy && typingIndex < 0 && (
          <div className="ai-bubble assistant">
            <div className="ai-bubble-content ai-typing">
              <span /> <span /> <span />
            </div>
          </div>
        )}
      </div>

      <form
        className="ai-inputbar"
        onSubmit={(e) => {
          e.preventDefault();
          ask(input);
        }}
      >
        <input
          className="ai-input"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="问 CINEAI 推荐一部电影"
          aria-label="给 CineAI 提问"
          autoFocus
        />
        <button className="button primary ai-search-btn" type="submit" disabled={busy || !input.trim()}>
          发送
        </button>
      </form>
      {error && <p className="ai-error">{error}</p>}
      <p className="ai-privacy-note">对话记录仅保存在当前浏览器（本机），不会上传或与他人共享。</p>
    </div>
  );
}
