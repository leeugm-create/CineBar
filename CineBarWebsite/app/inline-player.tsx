"use client";

import { useMemo, useState } from "react";
import type { Messages } from "./i18n";

export type WatchSource = {
  kind: "html5" | "hls";
  url: string;
  label: string;
  region?: string;
};

export type SearchHit = {
  type: "movie" | "tv";
  id: number;
  title: string;
  year: string;
  poster: string | null;
  rating: number | null;
  watch?: WatchSource[];
};

function safeSource(source: WatchSource | undefined): WatchSource | null {
  if (!source) return null;
  try {
    const url = new URL(source.url);
    if (url.protocol !== "https:") return null;
    return { ...source, url: url.href };
  } catch {
    return null;
  }
}

function posterURL(path: string | null): string | undefined {
  return path ? `https://image.tmdb.org/t/p/w500${path}` : undefined;
}

export default function InlinePlayer({
  hit,
  m,
  onClose,
}: {
  hit: SearchHit;
  m: Messages;
  onClose: () => void;
}) {
  const [armed, setArmed] = useState(false);
  const [failed, setFailed] = useState(false);
  const source = useMemo(() => safeSource(hit.watch?.[0]), [hit.watch]);
  const poster = posterURL(hit.poster);

  function retry() {
    setFailed(false);
    setArmed(false);
  }

  return (
    <section className="inline-player-card" aria-label={`${hit.title} ${m.playerSource}`}>
      <div className="inline-player-head">
        <div className="inline-player-title">
          <strong>{hit.title}</strong>
          <small>
            {hit.type === "movie" ? m.searchMovie : m.searchTV}
            {hit.year ? ` · ${hit.year.slice(0, 4)}` : ""}
          </small>
        </div>
        <button
          type="button"
          className="inline-player-close"
          onClick={onClose}
          aria-label={m.playerClose}
        >
          ×
        </button>
      </div>

      <div className="inline-player-stage">
        {source && armed && !failed ? (
          <video
            className="inline-player-video"
            controls
            playsInline
            preload="none"
            poster={poster}
            src={source.url}
            onError={() => setFailed(true)}
          />
        ) : (
          <div
            className="inline-player-poster"
            style={poster ? { backgroundImage: `url("${poster}")` } : undefined}
          >
            <div className="inline-player-overlay">
              {source && !failed ? (
                <button
                  type="button"
                  className="inline-player-play"
                  onClick={() => setArmed(true)}
                  aria-label={m.playerPlay}
                >
                  <span aria-hidden="true">▶</span>
                  {m.playerPlay}
                </button>
              ) : failed ? (
                <div className="inline-player-state inline-player-error">
                  <span>{m.playerError}</span>
                  <button type="button" className="inline-player-retry" onClick={retry}>
                    {m.playerRetry}
                  </button>
                </div>
              ) : (
                <p className="inline-player-state">{m.playerNoSource}</p>
              )}
            </div>
          </div>
        )}
      </div>

      <div className="inline-player-meta">
        <span>{source ? source.label : m.playerNoSource}</span>
        {source?.region ? <span>· {source.region}</span> : null}
      </div>
    </section>
  );
}
