"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Hls from "hls.js";

type CmsItem = {
  source: string;
  sourceName: string;
  id: string;
  title: string;
  year: string;
  poster: string | null;
  category: string;      // 原始 type_name，如 "喜剧片"
  episodeCount: number;
  remarks: string;       // "TC国语v2"/"正片" 等质量标签
  playFrom: string;
  playURL: string;       // "第01集$url#第02集$url"
  streamURL?: string;
  vodContent?: string;   // 简介（detail 接口才有）
};

type Line = {
  source: string;
  sourceName: string;
  id: string;
  title: string;
  remarks: string;
  streamURL: string | null;
  latency: number | null; // ms，null = 探测失败/超时
};

function proxiedPoster(raw: string): string {
  return `/api/cms/poster?url=${encodeURIComponent(raw)}`;
}

/** "第01集$url#第02集$url" → 集号数组（去掉空段）。 */
function parseEpisodes(playURL: string): string[] {
  return (playURL || "")
    .split("#")
    .map((seg) => seg.split("$")[0]?.trim())
    .filter(Boolean);
}

/** 取第 n 集的播放地址（n 从 1 起）。 */
function episodeURL(playURL: string, n: number): string | null {
  const seg = (playURL || "").split("#")[n - 1];
  if (!seg) return null;
  return seg.split("$")[1] ?? null;
}

/** 原始 type_name → 统一大类（与 worker cmsClassifyCategory 一致）。 */
function classifyCategory(raw: string): string {
  const t = raw || "";
  if (/短剧|迷你剧/.test(t)) return "drama";
  if (/动漫|动画/.test(t)) return "anime";
  if (/电影|片/.test(t)) return "movie";
  if (/剧|综艺|真人秀|纪录/.test(t)) return "tv";
  return "other";
}

/** 轻量延迟探测：no-cors GET 计时（m3u8 很小），8s 超时返回 null。 */
function probeLatency(url: string): Promise<number | null> {
  return new Promise((resolve) => {
    const ctrl = new AbortController();
    const timer = setTimeout(() => { ctrl.abort(); resolve(null); }, 8000);
    const start = performance.now();
    fetch(url, { mode: "no-cors", cache: "no-store", signal: ctrl.signal })
      .then(() => { clearTimeout(timer); resolve(Math.round(performance.now() - start)); })
      .catch(() => { clearTimeout(timer); resolve(null); });
  });
}

/** 播放器：对标 zip0，hls.js 播放 + 失败态 + 换线路。 */
function Player({
  item, episode, onEpisodeChange,
}: {
  item: CmsItem;
  episode: number;
  onEpisodeChange: (n: number) => void;
}) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  // 进入即播（zip0 风格）：armed 初始 true，视频自动加载；失败再显示错误态（2026-08-18）。
  const [armed, setArmed] = useState(true);
  const [failed, setFailed] = useState(false);
  const [failReason, setFailReason] = useState("");
  const [alt, setAlt] = useState<{ sourceName: string; url: string } | null>(null);
  const [searchingAlt, setSearchingAlt] = useState(false);

  const episodes = useMemo(() => parseEpisodes(item.playURL), [item.playURL]);
  const episodesFull = useMemo(
    () => (item.episodeCount > episodes.length ? Array.from({ length: item.episodeCount }, (_, i) => String(i + 1)) : episodes),
    [item.episodeCount, episodes]
  );

  const currentRaw = useMemo(() => {
    if (alt) return alt.url;
    return episodeURL(item.playURL, episode) ?? item.streamURL ?? null;
  }, [alt, item.playURL, item.streamURL, episode]);

  async function loadAlternate() {
    setSearchingAlt(true);
    try {
      const resp = await fetch(`/api/cms/search?q=${encodeURIComponent(item.title)}&episode=${episode}`);
      const body = (await resp.json()) as { results?: CmsItem[] };
      const others = (body.results ?? []).filter((r) => r.streamURL && r.source !== item.source);
      if (others.length > 0) {
        const pick = others[0];
        setAlt({ sourceName: pick.sourceName, url: pick.streamURL! });
        setFailed(false);
      } else {
        setFailReason("其他线路也没有可播地址");
      }
    } catch { /* 忽略 */ } finally { setSearchingAlt(false); }
  }

  useEffect(() => {
    if (!armed || !currentRaw) return;
    const video = videoRef.current;
    if (!video) return;
    let cancelled = false;
    let hls: Hls | null = null;
    let settled = false;
    const timeout = window.setTimeout(() => {
      if (!settled && !video.currentTime) { settled = true; setFailed(true); setFailReason("加载超时，请换线路"); }
    }, 12000);

    async function resolveAndPlay(raw: string) {
      let src = raw;
      if (!/\.m3u8(\?|$)/i.test(raw)) {
        try {
          const resp = await fetch(`/api/cms/stream?url=${encodeURIComponent(raw)}`);
          const body = (await resp.json()) as { streamURL?: string };
          if (cancelled) return;
          if (body.streamURL) src = body.streamURL;
          else { settled = true; window.clearTimeout(timeout); setFailed(true); setFailReason("无法解析播放地址"); return; }
        } catch { if (cancelled) return; settled = true; window.clearTimeout(timeout); setFailed(true); setFailReason("解析失败"); return; }
      }
      if (cancelled) return;
      if (Hls.isSupported()) {
        hls = new Hls({ maxBufferLength: 60, maxMaxBufferLength: 120, lowLatencyMode: false });
        hls.loadSource(src);
        hls.attachMedia(video);
        hls.on(Hls.Events.ERROR, (_e, data) => { if (data.fatal && !settled) { settled = true; window.clearTimeout(timeout); setFailed(true); setFailReason(`hls错误: ${data.type}/${data.details}`); } });
        hls.on(Hls.Events.MANIFEST_PARSED, () => { window.clearTimeout(timeout); video.play().catch(() => setFailed(true)); });
      } else if (video.canPlayType("application/vnd.apple.mpegurl")) { video.src = src; video.play().catch(() => setFailed(true)); }
      else { setFailed(true); setFailReason("浏览器不支持 m3u8"); }
    }
    resolveAndPlay(currentRaw);
    return () => { cancelled = true; window.clearTimeout(timeout); settled = true; hls?.destroy(); video.removeAttribute("src"); };
  }, [armed, currentRaw]);

  return (
    <div className="player-shell">
      <div className="player-frame">
        <video ref={videoRef} controls playsInline />
        {!armed || failed ? (
          <div className="player-overlay" style={{ backgroundImage: item.poster ? `url("${proxiedPoster(item.poster)}")` : undefined }}>
            <div className="player-overlay__shade">
              {!failed ? (
                <button type="button" className="player-play-btn" onClick={() => setArmed(true)}>▶ 播放</button>
              ) : (
                <div className="player-error">
                  <div className="player-error__title">该片源暂不可播，请换线路</div>
                  {failReason ? <div className="player-error__reason">{failReason}</div> : null}
                  <div className="player-error__actions">
                    <button type="button" className="player-error__btn player-error__btn--primary" onClick={loadAlternate} disabled={searchingAlt}>
                      {searchingAlt ? "查找中…" : "换线路"}
                    </button>
                    {alt ? (
                      <button type="button" className="player-error__btn" onClick={() => setAlt(null)}>回到当前线路</button>
                    ) : null}
                    <button type="button" className="player-error__btn" onClick={() => { setFailed(false); setArmed(true); }}>重试</button>
                  </div>
                </div>
              )}
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}

export default function WatchClient() {
  const [current, setCurrent] = useState<CmsItem | null>(null);
  const [lines, setLines] = useState<Line[]>([]);
  const [episode, setEpisode] = useState(1);
  const [related, setRelated] = useState<CmsItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [query, setQuery] = useState("");
  const [year, setYear] = useState("");
  const [probed, setProbed] = useState(false);

  const activeLineNo = useMemo(() => {
    const idx = lines.findIndex((l) => l.source === current?.source && l.id === current?.id);
    return idx >= 0 ? idx + 1 : null;
  }, [lines, current]);

  // 初始加载：解析 URL（source+id 精确直达 / title 搜索）
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const source = params.get("source");
    const id = params.get("id");
    const title = params.get("title") ?? params.get("q") ?? "";
    const year = params.get("year") ?? "";
    const ep = Number(params.get("episode")) || 1;
    setEpisode(ep);
    setQuery(title);
    setYear(year);
    const ctrl = new AbortController();

    async function load() {
      try {
        let item: CmsItem | null = null;
        if (source && id) {
          const r = await fetch(`/api/cms/detail?id=${encodeURIComponent(id)}&source=${encodeURIComponent(source)}`, { signal: ctrl.signal });
          if (r.ok) item = (await r.json()) as CmsItem;
          if (item) setQuery(item.title);
        } else if (title) {
          const r = await fetch(`/api/cms/search?q=${encodeURIComponent(title)}${year ? `&year=${encodeURIComponent(year)}` : ""}&episode=${ep}`, { signal: ctrl.signal });
          if (r.ok) {
            const body = (await r.json()) as { results?: CmsItem[] };
            const rs = (body.results ?? []).filter((x) => x.title && x.streamURL);
            if (rs.length > 0) {
              const prefer = rs.find((x) => x.source === "lzi" || x.source === "zuid");
              item = prefer ?? rs[0];
            }
          }
        }
        if (!item) { setNotFound(true); setLoading(false); return; }
        // 主数据（播放核心）到达：立即渲染播放器并自动播放，不等线路/推荐（2026-08-18 优化）。
        setCurrent(item);
        setLoading(false);
        // 线路列表：同片名多源聚合（含当前项），异步填充不阻塞播放
        void (async () => {
          try {
            const r = await fetch(`/api/cms/search?q=${encodeURIComponent(item.title)}${year ? `&year=${encodeURIComponent(year)}` : ""}&episode=${ep}`, { signal: ctrl.signal });
            if (r.ok) {
              const body = (await r.json()) as { results?: CmsItem[] };
              const rs = (body.results ?? []).filter((x) => x.title && x.streamURL);
              if (rs.length > 0) setLines(rs.map((x) => ({ source: x.source, sourceName: x.sourceName, id: x.id, title: x.title, remarks: x.remarks, streamURL: x.streamURL ?? null, latency: null })));
            }
          } catch { /* 忽略 */ }
        })();
        // 相关推荐：同分类热门，异步填充（最慢的接口放最后，绝不阻塞播放器）
        void (async () => {
          try {
            const cat = classifyCategory(item.category);
            const rl = await fetch(`/api/cms/list?category=${cat === "other" ? "movie" : cat}`, { signal: ctrl.signal });
            if (rl.ok) {
              const body = (await rl.json()) as { items?: CmsItem[] };
              setRelated((body.items ?? []).filter((x) => x.id !== item!.id || x.source !== item!.source).slice(0, 12));
            }
          } catch { /* 忽略 */ }
        })();
      } catch { /* 忽略 */ } finally { setLoading(false); }
    }
    load();
    return () => ctrl.abort();
  }, []);

  // 线路延迟探测：只探测非当前线路（当前项显示 "--" 或 "当前"）
  useEffect(() => {
    if (probed || lines.length === 0 || !current) return;
    setProbed(true);
    for (const line of lines) {
      if (line.source === current.source && line.id === current.id) continue;
      if (!line.streamURL) continue;
      probeLatency(line.streamURL).then((ms) => {
        setLines((prev) => prev.map((l) => (l.source === line.source && l.id === line.id ? { ...l, latency: ms } : l)));
      });
    }
  }, [lines.length, current, probed]);

  // 选集切换：更新 URL 并重置播放器
  const pickEpisode = useCallback((n: number) => {
    setEpisode(n);
    setAltReset();
    const sp = new URLSearchParams(window.location.search);
    sp.set("episode", String(n));
    window.history.replaceState(null, "", `${window.location.pathname}?${sp.toString()}`);
  }, []);

  function setAltReset() {
    // 通知 Player 重置 alt：通过 key 变化重建组件
    setPlayerKey((k) => k + 1);
  }
  const [playerKey, setPlayerKey] = useState(0);

  // 线路切换：整页跳转（zip0 式）
  function switchLine(line: Line) {
    window.location.href = `/watch?source=${encodeURIComponent(line.source)}&id=${encodeURIComponent(line.id)}&episode=${episode}`;
  }

  const episodes = useMemo(() => (current ? parseEpisodes(current.playURL) : []), [current]);
  const episodesFull = useMemo(
    () => (current && current.episodeCount > episodes.length ? Array.from({ length: current.episodeCount }, (_, i) => String(i + 1)) : episodes),
    [current, episodes]
  );

  if (loading) {
    // 骨架先行：播放器区域与布局立即呈现，数据到达后填充（避免长时间白屏/单行文案）。
    return (
      <div className="container watch-layout">
        <div className="watch-main">
          <div className="player-shell player-shell--loading" />
          <div className="now-playing">
            <div className="skeleton-bar" style={{ width: "55%", height: 22 }} />
          </div>
        </div>
        <aside className="watch-sidebar">
          <div className="source-panel source-panel--watch">
            <div className="source-panel__heading">播放来源</div>
            <div className="source-panel__empty">正在加载线路…</div>
          </div>
        </aside>
      </div>
    );
  }
  if (notFound || !current) {
    return <p className="watch-empty">未找到「{query}」的可播放资源</p>;
  }

  return (
    <div className="container watch-layout">
      <div className="watch-main">
        <Player key={playerKey} item={current} episode={episode} onEpisodeChange={pickEpisode} />

        <div className="now-playing">
          <div className="now-playing__summary">
            <span className="now-playing__label">NOW PLAYING</span>
            <h1 className="now-playing__title">{current.title}</h1>
            <span className="source-tag">线路 {activeLineNo ?? "—"}{current.remarks ? ` ${current.remarks}` : ""}</span>
            <span className="episode-nav">{episode} / {episodesFull.length || 1}</span>
          </div>
        </div>

        {episodesFull.length > 0 ? (
          <div className="episode-picker">
            <div className="episode-picker__heading">选集 {episodesFull.length} 集</div>
            <div className="episode-picker__list">
              {episodesFull.map((n, i) => (
                <button
                  key={n}
                  type="button"
                  className={`episode-btn${Number(n) === episode ? " is-active" : ""}`}
                  onClick={() => pickEpisode(Number(n))}
                >
                  {n}
                </button>
              ))}
            </div>
          </div>
        ) : null}

        <section className="detail-layout">
          {current.poster ? (
            <div className="detail-poster">
              <img src={proxiedPoster(current.poster)} alt={current.title} loading="lazy" />
            </div>
          ) : null}
          <div className="detail-copy">
            <h2>{current.title}</h2>
            <p className="detail-meta">
              {current.year ? <span>{current.year}</span> : null}
              {current.category ? <span>{current.category}</span> : null}
              {current.remarks ? <span className="detail-remarks">{current.remarks}</span> : null}
            </p>
            {current.vodContent ? <p className="detail-desc">{current.vodContent.replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").trim()}</p> : null}
          </div>
        </section>

        {related.length > 0 ? (
          <section className="related-videos">
            <h2>相关影视推荐</h2>
            <p className="related-videos__sub">为您精选同分类热门影片</p>
            <div className="video-card-grid">
              {related.map((x) => (
                <article className="video-card" key={`${x.source}-${x.id}`}>
                  <a
                    className="video-card__poster-link"
                    aria-label={`播放 ${x.title}`}
                    href={`/watch?source=${encodeURIComponent(x.source)}&id=${encodeURIComponent(x.id)}&episode=1`}
                  >
                    {x.poster ? <img className="video-card__poster" src={proxiedPoster(x.poster)} alt={x.title} loading="lazy" /> : <div className="video-card__poster video-card__poster--fallback">{x.title.slice(0, 2)}</div>}
                    <span className="video-card__play" aria-hidden="true">▶</span>
                    {x.remarks ? <span className="video-card__remarks">{x.remarks}</span> : null}
                  </a>
                  <div className="video-card__body">
                    <a className="video-card__title" href={`/watch?source=${encodeURIComponent(x.source)}&id=${encodeURIComponent(x.id)}&episode=1`}>{x.title}</a>
                    <div className="video-card__meta">{x.year ? `${x.year} · ` : ""}{x.category || "电影"}</div>
                  </div>
                </article>
              ))}
            </div>
          </section>
        ) : null}
      </div>

      <aside className="watch-sidebar">
        <aside className="source-panel source-panel--watch">
          <div className="source-panel__heading">播放来源</div>
          <p className="source-panel__hint">选择更合适的播放线路</p>
          <div className="source-panel__list">
            {lines.length === 0 ? (
              <div className="source-panel__empty">暂无其他线路</div>
            ) : (
              lines.map((line, i) => {
                const active = current.source === line.source && current.id === line.id;
                return (
                  <a
                    key={`${line.source}-${line.id}`}
                    className={`source-option${active ? " is-active" : ""}`}
                    href={active ? undefined : `/watch?source=${encodeURIComponent(line.source)}&id=${encodeURIComponent(line.id)}&episode=${episode}`}
                    onClick={active ? (e) => e.preventDefault() : undefined}
                  >
                    <span className="source-option__no">线路 {i + 1}</span>
                    {line.remarks ? <span className="source-option__tag">{line.remarks}</span> : <span className="source-option__tag">{line.sourceName}</span>}
                    <span className="source-option__ms">{active ? "当前" : line.latency != null ? `${line.latency} ms` : "—"}</span>
                  </a>
                );
              })
            )}
          </div>
        </aside>
      </aside>
    </div>
  );
}
