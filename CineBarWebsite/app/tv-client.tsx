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
  reachable?: boolean;
  webUnplayable?: boolean;
};

type IPTVGroup = {
  name: string;
  channels: IPTVChannel[];
};

/** 经 worker 代理的播放地址（服务端拉取 http 源 + 重写分片，解决混合内容/CORS）。 */
function proxiedStream(raw: string): string {
  return `/api/iptv/stream?url=${encodeURIComponent(raw)}`;
}

/** 经 worker 代理的台标地址（绕开 gitee 防盗链）。 */
function proxiedLogo(raw: string): string {
  return `/api/iptv/logo?url=${encodeURIComponent(raw)}`;
}

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
    let settled = false;
    // 加载超时：源代理 502 / 慢 / 卡死时，几秒内仍未开始播放就判定失败，避免"无限转圈"。
    const timeout = window.setTimeout(() => {
      if (!settled && !video.currentTime) {
        setFailed(true);
      }
    }, 9000);
    // 直播源经 worker /api/iptv/stream 代理后统一同源（含 CORS 与 m3u8 分片重写）。
    // 不再用 URL 后缀判断 HLS：央视等源是数字路径、经 302 指向咪咕 m3u8（2026-08-18 网页端央视全挂根因）。
    const source = proxiedStream(channel.url);
    if (Hls.isSupported()) {
      hls = new Hls({ enableWorker: true, lowLatencyMode: true, maxBufferLength: 30 });
      hls.loadSource(source);
      hls.attachMedia(video);
      hls.on(Hls.Events.ERROR, (_e, data) => {
        if (data.fatal) {
          settled = true;
          window.clearTimeout(timeout);
          if (data.details === "manifestLoadError") {
            // 不是 m3u8（可能是裸流）：降级原生播放尝试（Safari 可播 m3u8，Chrome 会触发 onerror 走失败态）。
            video.src = source;
            video.play().catch(() => setFailed(true));
            setLoaded(true);
          } else {
            setFailed(true);
          }
        }
      });
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        settled = true;
        window.clearTimeout(timeout);
        video.play().catch(() => setFailed(true));
        setLoaded(true);
      });
    } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = source;
      video.play().catch(() => setFailed(true));
      setLoaded(true);
    } else {
      setFailed(true);
    }
    return () => {
      settled = true;
      window.clearTimeout(timeout);
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
          // 对标 zip0：进入即自动播放第一个频道（跳过网页端不可播台，如央视 119.233.255.62 系）。
          setActiveGroup(body.groups[0].name);
          const firstPlayable = body.groups[0].channels.find((c) => !c.webUnplayable) ?? body.groups[0].channels[0] ?? null;
          setCurrent(firstPlayable);
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
    // 全部保留（含暂不可播的台，灰显标记）；worker 已按可达性排序，可播台在前。
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
    // 对标 zip0：切换分组后自动播放该组第一个可播频道（避免直接黑屏）。
    const first = group.channels.find((c) => c.reachable !== false && !c.webUnplayable) ?? group.channels[0];
    if (first) setCurrent(first);
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
                    className={`tv-station-card${current?.url === c.url ? " is-playing" : ""}${
                      c.reachable === false || c.webUnplayable ? " is-offline" : ""
                    }`}
                    onClick={() => choose(c)}
                  >
                    <span className="tv-station-logo-wrap">
                      {c.logo ? (
                        <img
                          src={proxiedLogo(c.logo)}
                          alt=""
                          loading="lazy"
                          onError={(e) => {
                            (e.currentTarget as HTMLImageElement).style.display = "none";
                          }}
                        />
                      ) : (
                        <span className="tv-station-fallback">{c.name.slice(0, 2)}</span>
                      )}
                      {c.reachable === false ? (
                        <span className="tv-station-offline-badge">{m.tvSignalUnavailable}</span>
                      ) : c.webUnplayable ? (
                        <span className="tv-station-offline-badge">请用 Mac 客户端</span>
                      ) : null}
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
