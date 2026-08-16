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

/** 电视台直播播放器：hls.js 播 m3u8 直播流，支持换台。 */
function LivePlayer({ channel }: { channel: IPTVChannel }) {
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
      hls = new Hls({ enableWorker: true, maxBufferLength: 30 });
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
    <div className="live-player">
      <div className="live-player__stage">
        <video ref={videoRef} className="live-player__video" controls playsInline autoPlay />
        {!loaded && !failed ? (
          <div className="live-player__state">
            <span className="live-spinner" aria-hidden="true" />
            <span>正在连接直播…</span>
          </div>
        ) : null}
        {failed ? (
          <div className="live-player__state live-player__error">
            <strong>直播源暂时不可用</strong>
            <span>可尝试切换其他频道，或稍后重试。</span>
            <button type="button" onClick={retry}>
              重试
            </button>
          </div>
        ) : null}
      </div>
      <div className="live-player__now">
        <span className="live-dot" aria-hidden="true" />
        <strong>{channel.name}</strong>
        {channel.responseTime ? <span>· {channel.responseTime}</span> : null}
        <span>· 直播</span>
      </div>
    </div>
  );
}

export default function TVClient({ m }: { m: Messages }) {
  const [groups, setGroups] = useState<IPTVGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [activeGroup, setActiveGroup] = useState<string>("");
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

  function choose(channel: IPTVChannel) {
    setCurrent(channel);
    window.scrollTo({ top: 0, behavior: "smooth" });
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
        <>
          {current ? <LivePlayer key={current.url} channel={current} /> : null}

          <div className="tv-body container">
            <nav className="tv-groups" aria-label={m.tvGroupsLabel}>
              {visibleGroups.map((g) => (
                <button
                  type="button"
                  key={g.name}
                  className={`tv-group-btn${activeGroup === g.name ? " is-active" : ""}`}
                  onClick={() => setActiveGroup(g.name)}
                >
                  {g.name}
                  <span>{g.channels.length}</span>
                </button>
              ))}
            </nav>

            {visibleGroups.map((g) => {
              if (activeGroup !== g.name) return null;
              return (
                <section key={g.name} className="tv-channel-section">
                  <h2>{g.name}</h2>
                  <div className="tv-channel-grid">
                    {g.channels.map((c) => (
                      <button
                        type="button"
                        key={`${c.name}-${c.url}`}
                        className={`tv-channel-card${current?.url === c.url ? " is-current" : ""}`}
                        onClick={() => choose(c)}
                      >
                        <span className="tv-channel-logo">
                          {c.logo ? (
                            <img src={c.logo} alt="" loading="lazy" onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = "none"; }} />
                          ) : (
                            <span aria-hidden="true">{c.name.slice(0, 2)}</span>
                          )}
                        </span>
                        <strong>{c.name}</strong>
                        <small>{c.responseTime || "直播"}</small>
                      </button>
                    ))}
                  </div>
                </section>
              );
            })}
          </div>
        </>
      )}
    </main>
  );
}
