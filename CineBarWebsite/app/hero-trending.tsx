"use client";

import { useEffect, useRef, useState } from "react";
import type { Locale, Messages } from "./i18n";

type TrendingMovie = {
  title: string;
  doubanID: string;
  rating: number;
  poster: string;
};

const releaseURL =
  "https://cinebar.cc/downloads/CineBar-0.9.0-test-build-98-universal.zip";

const isChinese = (locale: Locale) => locale === "zh-Hans" || locale === "zh-Hant";

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

  function itemHref(item: TrendingMovie): string {
    if (isChinese(locale) && item.doubanID) {
      return `https://www.douban.com/subject/${item.doubanID}/`;
    }
    return `https://www.themoviedb.org/search?query=${encodeURIComponent(item.title)}`;
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
            <a
              className="ht-card"
              key={`${kind}-${item.doubanID}`}
              href={itemHref(item)}
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
          ))}
        </div>
      )}
    </section>
  );
}
