"use client";

import { useEffect, useRef, useState } from "react";
import type { Messages } from "./i18n";

type TrendingMovie = {
  title: string;
  doubanID: string;
  rating: number;
  poster: string;
};

const releaseURL =
  "https://cinebar.cc/downloads/CineBar-0.9.0-test-build-89-universal.zip";

export default function HomeHero({ m }: { m: Messages }) {
  const [movies, setMovies] = useState<TrendingMovie[]>([]);
  const [shows, setShows] = useState<TrendingMovie[]>([]);
  const [posterLoaded, setPosterLoaded] = useState(false);

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

  const backdrop = movies.length > 0 ? movies[0].poster : "";

  return (
    <>
      <section className="hero hero-backdrop" id="top">
        {backdrop && (
          <div className="hero-backdrop-img">
            <img
              src={backdrop}
              alt=""
              aria-hidden="true"
              onLoad={() => setPosterLoaded(true)}
            />
          </div>
        )}
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
      />
      <TrendingRow
        title={m.trendingShows}
        items={shows}
        kind="tv"
      />
    </>
  );
}

function TrendingRow({
  title,
  items,
  kind,
}: {
  title: string;
  items: TrendingMovie[];
  kind: "movie" | "tv";
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
            <a
              className="ht-card"
              key={`${kind}-${item.doubanID}`}
              href={`https://www.douban.com/subject/${item.doubanID}/`}
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
