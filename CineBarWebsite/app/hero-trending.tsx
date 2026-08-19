"use client";

import { useCallback, useEffect, useRef, useState } from "react";

/** 自动刷新：页面可见且距上次加载超过 intervalMs 时自动重新加载；返回手动刷新函数。 */
function useAutoRefresh(load: () => void, intervalMs = 30 * 60 * 1000) {
  const lastLoad = useRef(Date.now());
  const loadRef = useRef(load);
  loadRef.current = load;
  useEffect(() => {
    function onVis() {
      if (document.visibilityState === "visible" && Date.now() - lastLoad.current > intervalMs) {
        lastLoad.current = Date.now();
        loadRef.current();
      }
    }
    document.addEventListener("visibilitychange", onVis);
    return () => document.removeEventListener("visibilitychange", onVis);
  }, [intervalMs]);
  return useCallback(() => {
    lastLoad.current = Date.now();
    loadRef.current();
  }, []);
}

/** 通用刷新按钮（区块标题右侧，与滚动按钮同风格）。 */
function RefreshButton({ onClick, refreshing }: { onClick: () => void; refreshing: boolean }) {
  return (
    <button
      type="button"
      className={`ht-nav-btn ht-refresh${refreshing ? " is-spinning" : ""}`}
      onClick={onClick}
      aria-label="刷新"
      title="刷新"
    >
      ⟳
    </button>
  );
}
import Link from "next/link";
import type { Locale, Messages } from "./i18n";
import type { ReactNode } from "react";

type TrendingMovie = {
  title: string;
  doubanID: string;
  rating: number;
  poster: string;
  tmdbId?: number;
  type?: "movie" | "tv";
  tmdbPoster?: string;
};

const releaseURL =
  "https://cinebar.cc/downloads/CineBar-0.9.0-test-build-142-universal.zip";

export default function HomeHero({ m, locale, heroExtra }: { m: Messages; locale: Locale; heroExtra?: ReactNode }) {
  const [movies, setMovies] = useState<TrendingMovie[]>([]);
  const [shows, setShows] = useState<TrendingMovie[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  const [tick, setTick] = useState(0);

  const loadTrending = useCallback((bypass: boolean) => {
    const controller = new AbortController();
    setRefreshing(true);
    // 初始加载吃缓存；手动/自动刷新带 _= 绕缓存拿最新
    const suffix = bypass ? `&_=${Date.now()}` : "";
    fetch(`/api/trending?type=all${suffix}`, { signal: controller.signal })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((body: { movies?: TrendingMovie[]; shows?: TrendingMovie[] }) => {
        setMovies(body.movies ?? []);
        setShows(body.shows ?? []);
      })
      .catch(() => {
        /* 网络失败时保持旧列表 */
      })
      .finally(() => setRefreshing(false));
    return () => controller.abort();
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    fetch(`/api/trending?type=all`, { signal: controller.signal })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((body: { movies?: TrendingMovie[]; shows?: TrendingMovie[] }) => {
        setMovies(body.movies ?? []);
        setShows(body.shows ?? []);
      })
      .catch(() => {
        /* 网络失败时保持空列表 */
      });
    return () => controller.abort();
  }, [tick]);

  const refreshTrending = useAutoRefresh(() => loadTrending(true));

  return (
    <>
      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="hero-version">{m.heroVersion}</p>
          <div className="hero-title">
            <h1>
              <span className="title-line">{m.heroTitle1}</span>
              <br />
              <span className="title-line">{m.heroTitle2}</span>
            </h1>
          </div>
          <p className="hero-lede">{m.heroLede}</p>
          <div className="hero-actions">
            <Link className="button primary ai-search-btn" href="/ai">
              <span className="ai-search-icon" aria-hidden="true">✦</span>
              {m.aiSearch}
            </Link>
            <a className="button link" href={releaseURL}>
              {m.download}
            </a>
          </div>
          <p className="hero-compat">{m.compat}</p>
        </div>
      </section>

      {/* 上次观看：主标下方、今日热门电影上方（用户要求的位置） */}
      {heroExtra}

      <TrendingRow
        title={m.trendingMovies}
        items={movies}
        kind="movie"
        locale={locale}
        refresh={<RefreshButton onClick={refreshTrending} refreshing={refreshing} />}
      />
      <NowPlayingRow locale={locale} />
      <TrendingRow
        title={m.trendingShows}
        items={shows}
        kind="tv"
        locale={locale}
      />
    </>
  );
}

/** 院线热门电影：优先豆瓣国内热映，抓不到回退 TMDB（稳定兜底）。 */
function NowPlayingRow({ locale }: { locale: Locale }) {
  const [items, setItems] = useState<{ title: string; year: string; rating: number | null; poster: string | null }[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  const [tick, setTick] = useState(0);

  const load = useCallback(async (bypass: boolean) => {
    setRefreshing(true);
    // 初始加载不带时间戳（吃 CDN 缓存，稳）；手动/自动刷新带 _= 绕缓存拿最新。
    const suffix = bypass ? `?_=${Date.now()}` : "";
    // 1) 豆瓣国内热映（更准，含国产片）
    try {
      const r = await fetch(`/api/nowplaying-cn${suffix}`, { signal: AbortSignal.timeout(8000) });
      if (r.ok) {
        const body = (await r.json()) as { items?: { title: string; year: string; rating: number | null; poster: string | null }[] };
        if (body.items && body.items.length > 0) { setItems(body.items); setRefreshing(false); return; }
      }
    } catch { /* 忽略 */ }
    // 2) 回退 TMDB（稳定，但可能缺国产片）
    try {
      const r2 = await fetch(`/api/nowplaying${suffix}`, { signal: AbortSignal.timeout(8000) });
      if (r2.ok) {
        const body2 = (await r2.json()) as { items?: { title: string; year: string; rating: number | null; poster: string | null }[] };
        setItems(body2.items ?? []);
      }
    } catch { /* 忽略 */ }
    setRefreshing(false);
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    void load(false);
    return () => controller.abort();
  }, [tick]);

  const refresh = useAutoRefresh(() => load(true));

  if (items.length === 0) return null;
  return (
    <section className="section ht-section">
      <div className="ht-head">
        <h2>院线热门电影</h2>
        <div className="ht-nav">
          <RefreshButton onClick={refresh} refreshing={refreshing} />
        </div>
      </div>
      <div className="ht-track">
        {items.map((it) => (
          <NowPlayingCard key={it.title} item={it} />
        ))}
      </div>
    </section>
  );
}

/** 院线热门单卡：zip0 风格。点击进独立播放页 /watch。 */
function NowPlayingCard({ item }: { item: { title: string; year: string; rating: number | null; poster: string | null } }) {
  const [posterFailed, setPosterFailed] = useState(false);
  // 豆瓣接口返回的 poster 已是 /api/cms/poster?url=… 代理路径（相对或绝对均可能），直接用；否则才包代理。
  const proxiedPoster = item.poster
    ? (item.poster.includes("/api/cms/poster?url=") ? item.poster : `/api/cms/poster?url=${encodeURIComponent(item.poster)}`)
    : null;
  return (
    <Link
      href={`/watch?title=${encodeURIComponent(item.title)}${item.year ? `&year=${encodeURIComponent(item.year)}` : ""}`}
      className="ht-card"
      aria-label={`播放 ${item.title}`}
    >
      {proxiedPoster && !posterFailed ? (
        <img className="ht-poster" src={proxiedPoster} alt={item.title} loading="lazy" onError={() => setPosterFailed(true)} />
      ) : (
        <div className="ht-poster ht-poster-fallback" style={{ background: "var(--background)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--muted)", fontSize: "30px", fontWeight: 700 }}>{item.title.slice(0, 2)}</div>
      )}
      <span className="ht-card-play" aria-hidden="true">▶</span>
      <span className="ht-card-meta">
        <strong>{item.title}</strong>
        <span className="ht-card-sub">
          {item.rating ? (
            <small className="ht-card-rating">★ {item.rating.toFixed(1)}</small>
          ) : (
            <small className="ht-card-type">{item.year || "电影"}</small>
          )}
        </span>
      </span>
    </Link>
  );
}

function TrendingRow({
  title,
  items,
  kind,
  locale,
  refresh,
}: {
  title: string;
  items: TrendingMovie[];
  kind: "movie" | "tv";
  locale: Locale;
  refresh?: ReactNode;
}) {
  const trackRef = useRef<HTMLDivElement>(null);

  function scrollByCards(offset: number) {
    const track = trackRef.current;
    if (!track) return;
    const card = track.querySelector<HTMLElement>(".ht-card");
    const step = (card ? card.offsetWidth + 16 : 260) * offset;
    track.scrollBy({ left: step, behavior: "smooth" });
  }

  return (
    <section className="section ht-section">
      <div className="ht-head">
        <h2>{title}</h2>
        <div className="ht-nav">
          {refresh}
          <button
            type="button"
            className="ht-nav-btn"
            onClick={() => scrollByCards(-7)}
            aria-label="向左"
          >
            ‹
          </button>
          <button
            type="button"
            className="ht-nav-btn"
            onClick={() => scrollByCards(7)}
            aria-label="向右"
          >
            ›
          </button>
        </div>
      </div>
      {items.length === 0 ? (
        <p className="ht-empty">加载中…</p>
      ) : (
        <div className="ht-track" ref={trackRef}>
          {items.slice(0, 10).map((item) => (
            <TrendingCard key={`${kind}-${item.doubanID}`} item={item} kind={kind} />
          ))}
        </div>
      )}
    </section>
  );
}

type TrendingCardItem = TrendingMovie;

/** 本周热门单卡：优先用 Moovie 数据已补齐的 tmdbId 跳自家详情页；
 *  若没有 tmdbId 则用 lookup 解析；都失败降级跳 Moovie。绝不跳豆瓣。 */
function TrendingCard({ item, kind }: { item: TrendingCardItem; kind: "movie" | "tv" }) {
  // 统一跳独立播放页 /watch?title=，点进去自动搜索并播放（对标 zip0）。
  const href = `/watch?title=${encodeURIComponent(item.title)}${item.year ? `&year=${encodeURIComponent(item.year)}` : ""}`;
  // 优先用 TMDB 海报（稳定），Moovie 豆瓣图代理兜底。
  const [posterFailed, setPosterFailed] = useState(false);
  const posterSrc = item.tmdbPoster || item.poster;
  // 海报统一走 cinebar.cc 代理（同源 + 加 CORS + 处理防盗链），避免 Moovie/豆瓣跨域失败。
  const proxiedPoster = posterSrc ? `/api/cms/poster?url=${encodeURIComponent(posterSrc)}` : null;
  const typeLabel = kind === "tv" ? "电视剧" : "电影";
  return (
    <a
      className="ht-card"
      href={href}
      aria-label={`播放 ${item.title}`}
    >
      {proxiedPoster && !posterFailed ? (
        <img
          className="ht-poster"
          src={proxiedPoster}
          alt={item.title}
          loading="lazy"
          onError={() => setPosterFailed(true)}
        />
      ) : (
        <div className="ht-poster ht-poster-fallback" style={{ background: "var(--background)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--muted)", fontSize: "30px", fontWeight: 700 }}>{item.title.slice(0, 2)}</div>
      )}
      <span className="ht-card-play" aria-hidden="true">▶</span>
      <span className="ht-card-meta">
        <strong>{item.title}</strong>
        <span className="ht-card-sub">
          {item.rating > 0 ? (
            <small className="ht-card-rating">★ {item.rating.toFixed(1)}</small>
          ) : (
            <small className="ht-card-type">{typeLabel}</small>
          )}
        </span>
      </span>
    </a>
  );
}
