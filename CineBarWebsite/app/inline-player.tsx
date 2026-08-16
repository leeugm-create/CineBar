"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Hls from "hls.js";
import { recordProgress, shouldWriteProgress } from "./watch-progress";
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
  const videoRef = useRef<HTMLVideoElement | null>(null);

  // m3u8 (HLS) 用 hls.js 挂载，跨浏览器可播（含 Chrome）；
  // 普通 HTML5 视频走原生 src。
  useEffect(() => {
    const video = videoRef.current;
    if (!video || !armed || !source || source.kind !== "hls") {
      return;
    }
    let hls: Hls | null = null;
    if (Hls.isSupported()) {
      hls = new Hls();
      hls.loadSource(source.url);
      hls.attachMedia(video);
      hls.on(Hls.Events.ERROR, (_event, data) => {
        if (data.fatal) setFailed(true);
      });
    } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = source.url;
    } else {
      setFailed(true);
    }
    return () => {
      hls?.destroy();
    };
  }, [armed, source]);

  const lastWriteRef = useRef(0);
  const resumeRef = useRef(0);

  // 续播：打开时若本地有进度，seek 到上次位置。
  useEffect(() => {
    if (!armed || !hit.title) return;
    try {
      const raw = window.localStorage.getItem("cinebar.watch.progress");
      if (!raw) return;
      const parsed = JSON.parse(raw) as { key: string; currentTime: number }[];
      if (!Array.isArray(parsed)) return;
      const key = `${hit.type}:${hit.title}:${hit.year}`;
      const found = parsed.find((x) => x && x.key === key);
      if (found && Number.isFinite(found.currentTime) && found.currentTime > 5) {
        resumeRef.current = found.currentTime;
      }
    } catch {
      // ignore
    }
  }, [armed, hit.title, hit.type, hit.year]);

  // 进度记录：timeupdate 节流（每 5 秒），暂停/关闭时也写。
  useEffect(() => {
    if (!armed || !source) return;
    const video = videoRef.current;
    if (!video) return;
    function write() {
      const t = video.currentTime;
      const d = video.duration;
      if (!Number.isFinite(t) || !Number.isFinite(d) || d <= 0 || t < 10) return;
      const now = Date.now();
      if (!shouldWriteProgress(lastWriteRef.current, now)) return;
      lastWriteRef.current = now;
      recordProgress({
        key: `${hit.type}:${hit.title}:${hit.year}`,
        type: hit.type,
        title: hit.title,
        year: hit.year,
        poster: hit.poster ?? null,
        sourceLabel: source.label,
        currentTime: t,
        duration: d,
        updatedAt: now,
      });
    }
    video.addEventListener("timeupdate", write);
    video.addEventListener("pause", write);
    return () => {
      write();
      video.removeEventListener("timeupdate", write);
      video.removeEventListener("pause", write);
    };
  }, [armed, source, hit.type, hit.title, hit.year, hit.poster]);

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
            ref={videoRef}
            className="inline-player-video"
            controls
            playsInline
            preload="none"
            poster={poster}
            src={source.kind === "html5" ? source.url : undefined}
            onError={() => setFailed(true)}
            onLoadedMetadata={(e) => {
              if (resumeRef.current > 0 && e.currentTarget.duration - resumeRef.current > 20) {
                e.currentTarget.currentTime = resumeRef.current;
              }
            }}
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
