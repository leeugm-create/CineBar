"use client";

import { useEffect, useRef, useState } from "react";
import type { Locale, Messages } from "./i18n";

type TrendingMovie = {
  title: string;
  doubanID: string;
  rating: number;
  poster: string;
  tmdbId?: number;
  type?: "movie" | "tv";
};

const releaseURL =
  "https://cinebar.cc/downloads/CineBar-0.9.0-test-build-119-universal.zip";

export default function HomeHero({ m, locale }: { m: Messages; locale: Locale }) {
  const [movies, setMovies] = useState<TrendingMovie[]>([]);
  const [shows, setShows] = useState<TrendingMovie[]>([]);

  useEffect(() => {
    const controller = new AbortController();
    fetch("/api/trending?type=all", { signal: controller.signal })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((body: { movies?: TrendingMovie[]; shows?: TrendingMovie[] }) => {
        setMovies(body.movies ?? []);
        setShows(body.shows ?? []);
      })
      .catch(() => {
        /* 网络失败时保持空列表 */
      });
    return () => controller.abort();
  }, []);

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
            <a className="button primary ai-search-btn" href="/ai">
              <span className="ai-search-icon" aria-hidden="true">✦</span>
              {m.aiSearch}
            </a>
            <a className="button link" href={releaseURL}>
              {m.download}
            </a>
          </div>
          <p className="hero-compat">{m.compat}</p>
        </div>
      </section>

      <TrendingRow
        title={m.trendingMovies}
        items={movies}
        kind="movie"
        locale={locale}
      />
      <TrendingRow
        title={m.trendingShows}
        items={shows}
        kind="tv"
        locale={locale}
      />
    </>
  );
}

function TrendingRow({
  title,
  items,
  kind,
  locale,
}: {
  title: string;
  items: TrendingMovie[];
  kind: "movie" | "tv";
  locale: Locale;
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
          {items.map((item) => (
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
  const [link, setLink] = useState<string | null>(() =>
    item.tmdbId ? `https://share.cinebar.cc/${item.type === "tv" ? "t" : "m"}/${item.tmdbId}?t=${encodeURIComponent(item.title)}` : null
  );

  useEffect(() => {
    if (item.tmdbId) return; // 已有 tmdbId，无需 lookup
    let alive = true;
    fetch(`/api/lookup?title=${encodeURIComponent(item.title)}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((body: { found?: boolean; type?: "movie" | "tv"; id?: number } | null) => {
        if (!alive) return;
        if (body && body.found && body.id != null) {
          const slug = body.type === "tv" ? "t" : "m";
          setLink(`https://share.cinebar.cc/${slug}/${body.id}?t=${encodeURIComponent(item.title)}`);
        } else {
          setLink(`https://moovie.c2v2.com/search?kw=${encodeURIComponent(item.title)}`);
        }
      })
      .catch(() => {
        if (alive) setLink(`https://moovie.c2v2.com/search?kw=${encodeURIComponent(item.title)}`);
      });
    return () => {
      alive = false;
    };
  }, [item.title, item.tmdbId]);

  const href = link ?? "#";
  return (
    <a
      className="ht-card"
      href={href}
      target="_blank"
      rel="noreferrer"
    >
      <img
        className="ht-poster"
        src={item.poster}
        alt={item.title}
        loading="lazy"
      />
      <span className="ht-card-meta">
        <strong>{item.title}</strong>
        {item.rating > 0 && (
          <small>★ {item.rating.toFixed(1)}</small>
        )}
      </span>
    </a>
  );
}
