"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Hls from "hls.js";

type CMSItem = {
  source: string;
  sourceName: string;
  id: string;
  title: string;
  year: string;
  poster: string | null;
  category: string;
  playURL: string;
  episodeCount: number;
};

type CMSDetail = CMSItem & {
  streamURL: string | null;
};

const CATEGORIES: { key: string; label: string }[] = [
  { key: "all", label: "全部" },
  { key: "movie", label: "电影" },
  { key: "tv", label: "电视剧" },
  { key: "drama", label: "短剧" },
  { key: "anime", label: "动漫" },
];

/** 海报地址代理（资源站图片可能防盗链，经 worker 中转）。 */
function proxiedPoster(raw: string): string {
  return `/api/cms/poster?url=${encodeURIComponent(raw)}`;
}

/** 浏览器端解析播放页：播放页 HTML 里有 `var main/const url = "/…index.m3u8?sign=…"`，
 *  用播放页域名拼出真实 m3u8。worker 抓国内播放页常被 Cloudflare 拒绝，而用户浏览器可直连。 */
async function resolvePlayPageInBrowser(pageURL: string): Promise<string | null> {
  try {
    const resp = await fetch(pageURL, { headers: { "user-agent": "Mozilla/5.0" } });
    if (!resp.ok) return null;
    const html = await resp.text();
    const m =
      html.match(/(?:var\s+main|const\s+url)\s*=\s*["']([^"']*\.m3u8[^"']*)["']/) ??
      html.match(/["']([^"']*index\.m3u8[^"']*)["']/);
    if (m && m[1]) {
      try {
        return new URL(m[1].replace(/\\\//g, "/"), new URL(pageURL)).toString();
      } catch {
        return null;
      }
    }
    // 回退：{page}/index.m3u8
    const page = new URL(pageURL);
    return `${page.origin}${page.pathname.replace(/\/$/, "")}/index.m3u8`;
  } catch {
    return null;
  }
}

/** 详情播放器：支持线路切换。播放失败时用标题搜其他源，自动尝试下一个可播线路。 */
function CmsPlayer({ detail, onClose }: { detail: CMSDetail; onClose: () => void }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [armed, setArmed] = useState(false);
  const [failed, setFailed] = useState(false);
  const [failReason, setFailReason] = useState("");
  const [episode, setEpisode] = useState(1);
  const [altIndex, setAltIndex] = useState(-1); // 当前用的备选线路下标；-1=主线路(detail)
  const [alts, setAlts] = useState<{ sourceName: string; url: string }[]>([]);
  const [searchingAlt, setSearchingAlt] = useState(false);
  const episodes = useMemo(() => {
    if (!detail.playURL) return [];
    // playURL 可能用 $$$ 分隔多条线路（同几集重复），只取第一条线路的集。
    const firstLine = detail.playURL.split("$$$")[0];
    return firstLine.split("#").map((s) => s.trim()).filter(Boolean);
  }, [detail.playURL]);
  // 当前实际要播的原始地址（detail 主线路或备选线路）
  const currentRaw = useMemo(() => {
    if (altIndex >= 0 && alts[altIndex]) return alts[altIndex].url;
    if (episode === 1 && detail.streamURL) return detail.streamURL;
    const target = episodes[Math.min(Math.max(episode, 1), episodes.length) - 1];
    if (!target) return detail.streamURL ?? null;
    const idx = target.indexOf("$");
    const raw = (idx < 0 ? target : target.slice(idx + 1).trim()) || "";
    return raw || null;
  }, [altIndex, alts, episode, episodes, detail.streamURL]);

  // 用标题搜其他源，收集可播线路。
  async function loadAlternates() {
    if (searchingAlt || !detail.title) return;
    setSearchingAlt(true);
    try {
      const resp = await fetch(`/api/cms/search?q=${encodeURIComponent(detail.title)}&episode=${episode}`);
      const body = (await resp.json()) as { results?: { sourceName: string; streamURL: string | null }[] };
      const others = (body.results ?? [])
        .filter((r) => r.streamURL) // 有流地址的
        .map((r) => ({ sourceName: r.sourceName, url: r.streamURL! }));
      setAlts(others);
      setAltIndex(0); // 切到第一个备选
      setFailed(false);
    } catch {
      // 搜不到其他源则保持现状
    } finally {
      setSearchingAlt(false);
    }
  }

  function nextAlternate() {
    setFailed(false);
    setAltIndex((i) => i + 1); // 切下一个备选（会触发 useEffect 重播）
  }

  // 播放：armed 后，把 currentRaw 解析成 m3u8 再 hls 播放；失败可换线路。
  useEffect(() => {
    if (!armed || !currentRaw) return;
    const video = videoRef.current;
    if (!video) return;
    let cancelled = false;
    let hls: Hls | null = null;
    let settled = false;
    const timeout = window.setTimeout(() => {
      if (!settled && !video.currentTime) {
        settled = true;
        setFailed(true);
        setFailReason("加载超时：源不可达或慢，请换线路");
      }
    }, 12000);

    async function resolveAndPlay(raw: string) {
      let src = raw;
      if (!/\.m3u8(\?|$)/i.test(raw)) {
        try {
          const resp = await fetch(`/api/cms/stream?url=${encodeURIComponent(raw)}`);
          const body = (await resp.json()) as { streamURL?: string };
          if (cancelled) return;
          if (body.streamURL) src = body.streamURL;
          else {
            settled = true;
            window.clearTimeout(timeout);
            setFailed(true);
            setFailReason("无法解析该片播放地址");
            return;
          }
        } catch {
          if (cancelled) return;
          settled = true;
          window.clearTimeout(timeout);
          setFailed(true);
          setFailReason("解析播放地址失败");
          return;
        }
      }
      if (cancelled) return;
      if (Hls.isSupported()) {
        hls = new Hls({ maxBufferLength: 60, maxMaxBufferLength: 120, lowLatencyMode: false });
        hls.loadSource(src);
        hls.attachMedia(video);
        hls.on(Hls.Events.ERROR, (_e, data) => {
          if (data.fatal && !settled) {
            settled = true;
            window.clearTimeout(timeout);
            setFailed(true);
            setFailReason(`hls错误: ${data.type}/${data.details}`);
          }
        });
        hls.on(Hls.Events.MANIFEST_PARSED, () => {
          window.clearTimeout(timeout);
          video.play().catch(() => setFailed(true));
        });
      } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
        video.src = src;
        video.play().catch(() => setFailed(true));
      } else {
        setFailed(true);
        setFailReason("浏览器不支持 m3u8");
      }
    }
    resolveAndPlay(currentRaw);

    return () => {
      cancelled = true;
      window.clearTimeout(timeout);
      settled = true;
      hls?.destroy();
      video.removeAttribute("src");
    };
  }, [armed, currentRaw]);

  function changeEpisode(n: number) {
    setEpisode(n);
    setFailed(false);
    setArmed(true);
    setAltIndex(-1); // 离开换线路状态，用当前集的原地址
  }

  return (
    <section style={{ background: "#0d1117", border: "1px solid rgba(255,255,255,0.12)", borderRadius: "14px", padding: "14px", marginTop: "16px" }}>
      {/* 标题栏 */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "12px" }}>
        <div>
          <strong style={{ fontSize: "16px", color: "#fff" }}>{detail.title}</strong>
          <small style={{ display: "block", color: "#9aa" }}>
            {detail.category}
            {detail.year ? ` · ${detail.year}` : ""}
            {episodes.length ? ` · 共 ${episodes.length} 集` : ""}
          </small>
        </div>
        <button type="button" onClick={onClose} aria-label="关闭" style={{ background: "none", border: "none", color: "#aaa", fontSize: "22px", cursor: "pointer" }}>
          ×
        </button>
      </div>

      {/* 播放器：固定 16:9，黑底 */}
      <div style={{ position: "relative", width: "100%", aspectRatio: "16/9", background: "#000", borderRadius: "10px", overflow: "hidden" }}>
        <video ref={videoRef} controls playsInline style={{ width: "100%", height: "100%", display: "block" }} />
        {!armed || failed ? (
          <div style={{ position: "absolute", inset: 0, background: "#161a2b", backgroundImage: detail.poster ? `url("${proxiedPoster(detail.poster)}")` : undefined, backgroundSize: "cover", backgroundPosition: "center" }}>
            <div style={{ position: "absolute", inset: 0, background: "rgba(0,0,0,0.6)", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "10px" }}>
              {!failed ? (
                <button type="button" onClick={() => setArmed(true)} style={{ padding: "12px 28px", fontSize: "16px", fontWeight: 700, background: "#f97316", color: "#fff", border: "none", borderRadius: "999px", cursor: "pointer" }}>
                  <span aria-hidden="true">▶</span> {episode > 1 ? `播放第 ${episode} 集` : "播放"}
                </button>
              ) : (
                <div style={{ color: "#fff", textAlign: "center" }}>
                  <div style={{ fontWeight: 700, color: "#ff6b6b" }}>该片源暂不可播，请换线路</div>
                  {failReason ? <div style={{ fontSize: "12px", color: "#ffb", marginTop: "6px" }}>{failReason}</div> : null}
                  {currentRaw ? <div style={{ fontSize: "11px", color: "#99a", marginTop: "4px", wordBreak: "break-all" }}>源地址: {currentRaw.slice(0, 100)}</div> : null}
                  <div style={{ display: "flex", gap: "8px", justifyContent: "center", marginTop: "10px", flexWrap: "wrap" }}>
                    {searchingAlt ? (
                      <span style={{ color: "#aaa", fontSize: "13px" }}>正在查找其它线路…</span>
                    ) : (
                      <button type="button" onClick={loadAlternates} style={{ padding: "6px 16px", background: "#f97316", color: "#fff", border: "none", borderRadius: "6px", cursor: "pointer" }}>
                        换线路
                      </button>
                    )}
                    {alts.length > 0 ? (
                      <button type="button" onClick={nextAlternate} style={{ padding: "6px 16px", background: "#333", color: "#fff", border: "none", borderRadius: "6px", cursor: "pointer" }}>
                        下一个线路({alts[altIndex]?.sourceName ?? ""})
                      </button>
                    ) : null}
                    <button type="button" onClick={() => setArmed(false)} style={{ padding: "6px 16px", background: "#333", color: "#fff", border: "none", borderRadius: "6px", cursor: "pointer" }}>重试</button>
                  </div>
                </div>
              )}
            </div>
          </div>
        ) : null}
      </div>

      {/* 选集 */}
      {episodes.length > 1 ? (
        <div style={{ display: "flex", flexWrap: "wrap", gap: "6px", marginTop: "12px" }}>
          {episodes.map((ep, i) => {
            const label = ep.split("$")[0] || `第${i + 1}集`;
            return (
              <button
                type="button"
                key={i}
                onClick={() => changeEpisode(i + 1)}
                style={{ padding: "5px 10px", fontSize: "12px", background: i + 1 === episode ? "#f97316" : "#222", color: "#fff", border: "none", borderRadius: "6px", cursor: "pointer" }}
              >
                {label}
              </button>
            );
          })}
        </div>
      ) : null}
    </section>
  );
}

export default function VideosClient() {
  const [category, setCategory] = useState("all");
  const [items, setItems] = useState<CMSItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [current, setCurrent] = useState<CMSDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [query, setQuery] = useState("");
  const [searching, setSearching] = useState(false);
  const [searchResults, setSearchResults] = useState<CMSItem[]>([]);

  const load = useCallback(async (cat: string) => {
    setLoading(true);
    setError(false);
    try {
      const resp = await fetch(`/api/cms/list?category=${cat}&pg=1`);
      if (!resp.ok) throw new Error(String(resp.status));
      const body = (await resp.json()) as { items: CMSItem[] };
      setItems(body.items ?? []);
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load(category);
  }, [category, load]);

  // 支持 URL ?q= 自动搜索（首页短剧卡片点进来直接搜该片）。
  useEffect(() => {
    if (typeof window === "undefined") return;
    const params = new URLSearchParams(window.location.search);
    const q = params.get("q");
    if (q) {
      setQuery(q);
      // 用 q 触发一次搜索
      fetch(`/api/cms/search?q=${encodeURIComponent(q)}&episode=1`)
        .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
        .then((body: { results?: (Omit<CMSItem, "streamURL"> & { streamURL?: string })[] }) => {
          const merged: CMSItem[] = [];
          for (const r of body.results ?? []) {
            if (!r.title || !r.streamURL) continue;
            merged.push({ ...r, playURL: "", episodeCount: 0 });
          }
          setSearchResults(merged);
          // 自动打开第一个结果播放
          if (merged.length > 0) openItem(merged[0]);
        })
        .catch(() => {});
    }
  }, []);

  // 搜索：CineCMS 多源为主，Moovie(/api/play) 兜底，合并展示。
  async function doSearch() {
    const q = query.trim();
    if (!q) return;
    setSearching(true);
    const merged: CMSItem[] = [];
    try {
      const resp = await fetch(`/api/cms/search?q=${encodeURIComponent(q)}&episode=1`);
      if (resp.ok) {
        const body = (await resp.json()) as { results?: (Omit<CMSItem, "streamURL"> & { streamURL?: string })[] };
        for (const r of body.results ?? []) {
          if (!r.title || !r.streamURL) continue;
          merged.push({ ...r, playURL: "", episodeCount: 0 });
        }
      }
    } catch { /* ignore */ }
    // Moovie 兜底：CineCMS 无结果时尝试。
    if (merged.length === 0) {
      try {
        const resp = await fetch(`/api/play?title=${encodeURIComponent(q)}&year=`);
        if (resp.ok) {
          const src = (await resp.json()) as { url?: string; label?: string };
          if (src.url) {
            merged.push({
              source: "moovie", sourceName: "Moovie", id: `moovie-${q}`,
              title: q, year: "", poster: null, category: "搜索",
              playURL: "", episodeCount: 0,
            });
          }
        }
      } catch { /* ignore */ }
    }
    setSearchResults(merged);
    setSearching(false);
  }

  async function openItem(item: CMSItem) {
    setDetailLoading(true);
    setCurrent(null);
    try {
      if (item.source === "moovie") {
        // Moovie 源：直接调 /api/play 取流。
        const resp = await fetch(`/api/play?title=${encodeURIComponent(item.title)}&year=${encodeURIComponent(item.year)}`);
        const src = (await resp.json()) as { url?: string; label?: string };
        setCurrent({ ...item, streamURL: src.url ?? null, playURL: "" });
      } else {
        // 必须带 source：不同源的同 id 是不同片，按源精确查询，避免张冠李戴。
        const resp = await fetch(
          `/api/cms/detail?id=${encodeURIComponent(item.id)}&source=${encodeURIComponent(item.source)}`
        );
        if (!resp.ok) throw new Error(String(resp.status));
        const detail = (await resp.json()) as CMSDetail;
        setCurrent(detail);
      }
    } catch {
      setCurrent({ ...item, streamURL: null });
    } finally {
      setDetailLoading(false);
    }
  }

  const visibleItems = useMemo(() => {
    if (category === "all") return items;
    // 后端返回的 category 是原始 type_name（含"短剧/动漫/电影/剧"等），按关键词匹配。
    const target: Record<string, string[]> = {
      movie: ["电影", "片"],
      tv: ["剧", "综艺", "真人秀"],
      drama: ["短剧", "迷你剧"],
      anime: ["动漫", "动画"],
    };
    const keys = target[category] ?? [];
    return items.filter((i) => keys.some((k) => i.category.includes(k)));
  }, [items, category]);

  return (
    <main className="videos-page">
      <section className="tv-hero">
        <div className="container tv-hero__inner">
          <span className="eyebrow">VIDEOS</span>
          <h1>影视库</h1>
          <p>电影、电视剧、短剧与动漫，来自多个公开资源站聚合。</p>
          <input
            className="tv-search"
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") doSearch(); }}
            placeholder="搜索电影 / 电视剧 / 短剧 / 动漫…"
            aria-label="搜索影视"
            style={{ maxWidth: "480px", width: "100%", marginTop: "12px" }}
          />
        </div>
      </section>

      {/* 版本标记：确认是否加载到最新前端（诊断缓存用） */}
      <div style={{ background: "#22c55e", color: "#000", padding: "8px 16px", fontWeight: 700, textAlign: "center" }}>
        播放器版本 v8.0（搜索功能：CineCMS+Moovie合并）
      </div>

      <div className="container">
        <div className="videos-cats" role="tablist">
          {CATEGORIES.map((c) => (
            <button
              key={c.key}
              type="button"
              role="tab"
              aria-selected={category === c.key}
              className={`videos-cat${category === c.key ? " is-active" : ""}`}
              onClick={() => setCategory(c.key)}
            >
              {c.label}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="tv-loading">
            <span className="live-spinner" aria-hidden="true" />
            <span>正在载入影视列表…</span>
          </div>
        ) : error ? (
          <div className="tv-error">
            <strong>载入失败</strong>
            <span>请稍后重试</span>
          </div>
        ) : current ? (
          <CmsPlayer detail={current} onClose={() => setCurrent(null)} />
        ) : detailLoading ? (
          <div className="tv-loading">
            <span className="live-spinner" aria-hidden="true" />
            <span>正在解析播放地址…</span>
          </div>
        ) : searching ? (
          <div className="tv-loading">
            <span className="live-spinner" aria-hidden="true" />
            <span>正在搜索…</span>
          </div>
        ) : query.trim() ? (
          <div className="tv-station-grid videos-grid videos-grid--zip0">
            {searchResults.map((item) => (
              <a
                key={`${item.source}-${item.id}`}
                className="ht-card"
                href={`/watch?title=${encodeURIComponent(item.title)}${item.year ? `&year=${encodeURIComponent(item.year)}` : ""}`}
                aria-label={`播放 ${item.title}`}
              >
                {item.poster ? (
                  <img className="ht-poster" src={proxiedPoster(item.poster)} alt={item.title} loading="lazy" onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = "none"; }} />
                ) : (
                  <div className="ht-poster ht-poster-fallback" style={{ background: "var(--background)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--muted)", fontSize: "30px", fontWeight: 700 }}>{item.title.slice(0, 2)}</div>
                )}
                <span className="ht-card-play" aria-hidden="true">▶</span>
                <span className="ht-card-meta">
                  <strong>{item.title}</strong>
                  <span className="ht-card-sub">
                    <small className="ht-card-type">{item.category} · {item.sourceName}</small>
                  </span>
                </span>
              </a>
            ))}
            {searchResults.length === 0 ? (
              <div className="tv-error">
                <span>未找到相关影视，换个关键词试试</span>
              </div>
            ) : null}
          </div>
        ) : (
          <div className="tv-station-grid videos-grid videos-grid--zip0">
            {visibleItems.map((item) => (
              <a
                key={`${item.source}-${item.id}`}
                className="ht-card"
                href={`/watch?title=${encodeURIComponent(item.title)}${item.year ? `&year=${encodeURIComponent(item.year)}` : ""}`}
                aria-label={`播放 ${item.title}`}
              >
                {item.poster ? (
                  <img className="ht-poster" src={proxiedPoster(item.poster)} alt={item.title} loading="lazy" onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = "none"; }} />
                ) : (
                  <div className="ht-poster ht-poster-fallback" style={{ background: "var(--background)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--muted)", fontSize: "30px", fontWeight: 700 }}>{item.title.slice(0, 2)}</div>
                )}
                <span className="ht-card-play" aria-hidden="true">▶</span>
                <span className="ht-card-meta">
                  <strong>{item.title}</strong>
                  <span className="ht-card-sub">
                    <small className="ht-card-type">{item.category}{item.remarks ? ` · ${item.remarks}` : ""}</small>
                  </span>
                </span>
              </a>
            ))}
            {visibleItems.length === 0 ? (
              <div className="tv-error">
                <span>该分类暂无内容</span>
              </div>
            ) : null}
          </div>
        )}
      </div>
    </main>
  );
}
