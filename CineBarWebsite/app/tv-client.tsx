"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Hls from "hls.js";
import type { Messages } from "./i18n";

type IPTVChannel = {
  name: string;
  logo: string | null;
  url: string;
  group: string;
  responseTime: string;
};

type IPTVGroup = {
  name: string;
  channels: IPTVChannel[];
};

function fmt(template: string, n: number): string {
  return template.replace("{n}", String(n));
}

/** 播放器舞台（对标 zip0 player-shell）：16:9 黑底 + 加载/失败遮罩。 */
function LivePlayer({ channel, m }: { channel: IPTVChannel; m: Messages }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [failed, setFailed] = useState(false);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    setFailed(false);
    setLoaded(false);
    let hls: Hls | null = null;
    const isHLS = channel.url.toLowerCase().includes(".m3u8");
    if (isHLS && Hls.isSupported()) {
      hls = new Hls({ enableWorker: true, lowLatencyMode: true, maxBufferLength: 30 });
      hls.loadSource(channel.url);
      hls.attachMedia(video);
      hls.on(Hls.Events.ERROR, (_e, data) => {
        if (data.fatal) setFailed(true);
      });
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        video.play().catch(() => setFailed(true));
        setLoaded(true);
      });
    } else if (video.canPlayType("application/vnd.apple.mpegurl") || !isHLS) {
      video.src = channel.url;
      video.play().catch(() => setFailed(true));
      setLoaded(true);
    } else {
      setFailed(true);
    }
    return () => {
      hls?.destroy();
      video.removeAttribute("src");
    };
  }, [channel.url]);

  function retry() {
    setFailed(false);
    const video = videoRef.current;
    if (!video) return;
    video.load();
    video.play().catch(() => setFailed(true));
  }

  return (
    <div className="player-shell">
      <div className="artplayer-container">
        <video ref={videoRef} className="live-player__video" controls playsInline autoPlay />
      </div>
      {!loaded && !failed ? (
        <div className="player-state">
          <div className="player-state__loading">
            <span className="live-spinner" aria-hidden="true" />
            <span>{m.tvConnecting}</span>
          </div>
        </div>
      ) : null}
      {failed ? (
        <div className="player-state player-state--error">
          <strong>{m.tvSignalError}</strong>
          <span>{m.tvChooseOther}</span>
          <button type="button" onClick={retry}>
            {m.tvRetry}
          </button>
        </div>
      ) : null}
    </div>
  );
}

export default function TVClient({ m }: { m: Messages }) {
  const [groups, setGroups] = useState<IPTVGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [activeGroup, setActiveGroup] = useState("");
  const [current, setCurrent] = useState<IPTVChannel | null>(null);
  const [query, setQuery] = useState("");

  useEffect(() => {
    let alive = true;
    fetch("/api/iptv", { headers: { accept: "application/json" } })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((body: { groups: IPTVGroup[] }) => {
        if (!alive) return;
        setGroups(body.groups ?? []);
        if (body.groups?.length) {
          // 对标 zip0：进入即自动播放第一个频道。
          setActiveGroup(body.groups[0].name);
          setCurrent(body.groups[0].channels[0] ?? null);
        }
      })
      .catch(() => {
        if (alive) setError(true);
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, []);

  const visibleGroups = useMemo(() => {
    if (!query.trim()) return groups;
    const q = query.trim().toLowerCase();
    return groups
      .map((g) => ({
        ...g,
        channels: g.channels.filter((c) => c.name.toLowerCase().includes(q)),
      }))
      .filter((g) => g.channels.length > 0);
  }, [groups, query]);

  const activeChannels = useMemo(() => {
    const g = visibleGroups.find((x) => x.name === activeGroup) ?? visibleGroups[0];
    return g?.channels ?? [];
  }, [visibleGroups, activeGroup]);

  const activeGroupName = useMemo(() => {
    const g = visibleGroups.find((x) => x.name === activeGroup) ?? visibleGroups[0];
    return g?.name ?? "";
  }, [visibleGroups, activeGroup]);

  function choose(channel: IPTVChannel) {
    setCurrent(channel);
  }

  function switchGroup(group: IPTVGroup) {
    setActiveGroup(group.name);
    // 对标 zip0：切换分组后自动播放该组第一个频道。
    if (group.channels.length) setCurrent(group.channels[0]);
  }

  return (
    <main className="tv-page">
      <section className="tv-hero">
        <div className="container tv-hero__inner">
          <span className="eyebrow">LIVE TV</span>
          <h1>{m.tvTitle}</h1>
          <p>{m.tvLede}</p>
          <input
            className="tv-search"
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={m.tvSearchPlaceholder}
            aria-label={m.tvSearchPlaceholder}
          />
        </div>
      </section>

      {loading ? (
        <div className="tv-loading container">
          <span className="live-spinner" aria-hidden="true" />
          <span>{m.tvLoading}</span>
        </div>
      ) : error ? (
        <div className="tv-error container">
          <strong>{m.tvErrorTitle}</strong>
          <span>{m.tvErrorBody}</span>
        </div>
      ) : (
        <div className="watch-layout container">
          {/* 左栏：播放器 + 当前频道 + 频道列表 */}
          <div className="watch-main">
            {current ? <LivePlayer key={current.url} channel={current} m={m} /> : null}

            {current ? (
              <div className="now-playing">
                <div className="now-playing__summary">
                  <div>
                    <span className="eyebrow">{m.tvNowPlaying}</span>
                    <h1>{current.name}</h1>
                    <p>
                      {current.group} · {m.tvAllDaySignal}
                    </p>
                  </div>
                </div>
              </div>
            ) : null}

            <section className="related-videos">
              <div className="related-videos__heading">
                <h2>
                  {activeGroupName} {m.tvChannelList}
                </h2>
                <span>{fmt(m.tvChannelCount, activeChannels.length)}</span>
              </div>
              <div className="tv-station-grid">
                {activeChannels.map((c) => (
                  <button
                    type="button"
                    key={`${c.name}-${c.url}`}
                    className={`tv-station-card${current?.url === c.url ? " is-playing" : ""}`}
                    onClick={() => choose(c)}
                  >
                    <span className="tv-station-logo-wrap">
                      {c.logo ? (
                        <img
                          src={c.logo}
                          alt=""
                          loading="lazy"
                          onError={(e) => {
                            (e.currentTarget as HTMLImageElement).style.display = "none";
                          }}
                        />
                      ) : (
                        <span className="tv-station-fallback">{c.name.slice(0, 2)}</span>
                      )}
                    </span>
                    <span className="tv-station-info">
                      <strong>{c.name}</strong>
                      <small>
                        {c.group} · {m.tvLiveSource}
                      </small>
                    </span>
                  </button>
                ))}
              </div>
            </section>
          </div>

          {/* 右栏：切换分组侧边栏（对标 zip0 source-panel--watch） */}
          <aside className="watch-sidebar">
            <div className="source-panel source-panel--watch">
              <div className="source-panel__heading">
                <svg viewBox="0 0 24 24" width="19" height="19" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
                  <circle cx="12" cy="12" r="10" />
                  <path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20" />
                  <path d="M2 12h20" />
                </svg>
                <div>
                  <strong>{m.tvSwitchGroups}</strong>
                  <span>{fmt(m.tvGroupCount, visibleGroups.length)}</span>
                </div>
              </div>
              <div className="source-panel__list">
                {visibleGroups.map((g) => (
                  <button
                    type="button"
                    key={g.name}
                    className={`source-option${activeGroup === g.name ? " is-active" : ""}`}
                    onClick={() => switchGroup(g)}
                  >
                    <span className="source-option__content">
                      <strong>{g.name}</strong>
                      <div className="source-option__meta">
                        <span>
                          {g.channels.length} {m.tvStationCount}
                        </span>
                      </div>
                    </span>
                  </button>
                ))}
              </div>
            </div>
          </aside>
        </div>
      )}
    </main>
  );
}
