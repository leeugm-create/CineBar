"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Hls from "hls.js";

type CMSItem = {
  source: string;
  sourceName: string;
  id: string;
  title: string;
  year: string;
  poster: string | null;
  category: string;
  playURL: string;
  episodeCount: number;
};

type CMSDetail = CMSItem & {
  streamURL: string | null;
};

const CATEGORIES: { key: string; label: string }[] = [
  { key: "all", label: "全部" },
  { key: "movie", label: "电影" },
  { key: "tv", label: "电视剧" },
  { key: "drama", label: "短剧" },
  { key: "anime", label: "动漫" },
];

/** 海报地址代理（资源站图片可能防盗链，经 worker 中转）。 */
function proxiedPoster(raw: string): string {
  return `/api/cms/poster?url=${encodeURIComponent(raw)}`;
}

/** 详情播放器：m3u8 用 hls.js，带加载/失败遮罩。 */
function CmsPlayer({ detail, onClose }: { detail: CMSDetail; onClose: () => void }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [armed, setArmed] = useState(false);
  const [failed, setFailed] = useState(false);
  const [episode, setEpisode] = useState(1);
  const episodes = useMemo(() => {
    if (!detail.playURL) return [];
    return detail.playURL.split("#").map((s) => s.trim()).filter(Boolean);
  }, [detail.playURL]);

  const currentStream = useMemo(() => {
    if (!detail.playURL || episodes.length === 0) return null;
    const target = episodes[Math.min(Math.max(episode, 1), episodes.length) - 1];
    const idx = target.indexOf("$");
    return idx < 0 ? target : target.slice(idx + 1).trim() || null;
  }, [detail.playURL, episodes, episode]);

  useEffect(() => {
    if (!armed || !currentStream) return;
    setFailed(false);
    const video = videoRef.current;
    if (!video) return;
    let hls: Hls | null = null;
    if (Hls.isSupported()) {
      hls = new Hls();
      hls.loadSource(currentStream);
      hls.attachMedia(video);
      hls.on(Hls.Events.ERROR, (_e, data) => {
        if (data.fatal) setFailed(true);
      });
      video.play().catch(() => setFailed(true));
    } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = currentStream;
      video.play().catch(() => setFailed(true));
    } else {
      setFailed(true);
    }
    return () => {
      hls?.destroy();
      video.removeAttribute("src");
    };
  }, [armed, currentStream]);

  function changeEpisode(n: number) {
    setEpisode(n);
    setArmed(true);
  }

  return (
    <section className="player-shell cms-player">
      <div className="cms-player-head">
        <div className="cms-player-title">
          <strong>{detail.title}</strong>
          <small>
            {detail.category}
            {detail.year ? ` · ${detail.year}` : ""}
            {episodes.length ? ` · 共 ${episodes.length} 集` : ""}
          </small>
        </div>
        <button type="button" className="inline-player-close" onClick={onClose} aria-label="关闭">
          ×
        </button>
      </div>

      <div className="inline-player-stage">
        {armed && !failed ? (
          <video
            ref={videoRef}
            className="inline-player-video"
            controls
            playsInline
            autoPlay
          />
        ) : (
          <div
            className="inline-player-poster"
            style={detail.poster ? { backgroundImage: `url("${proxiedPoster(detail.poster)}")` } : undefined}
          >
            <div className="inline-player-overlay">
              {!failed ? (
                <button type="button" className="inline-player-play" onClick={() => setArmed(true)}>
                  <span aria-hidden="true">▶</span>
                  {episode > 1 ? `播放第 ${episode} 集` : "播放"}
                </button>
              ) : (
                <div className="inline-player-state inline-player-error">
                  <span>该片源暂不可播，请换一部或换线路</span>
                  <button type="button" className="inline-player-retry" onClick={() => setArmed(false)}>
                    重试
                  </button>
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      {episodes.length > 1 ? (
        <div className="cms-episodes">
          {episodes.map((ep, i) => {
            const label = ep.split("$")[0] || `第${i + 1}集`;
            return (
              <button
                type="button"
                key={i}
                className={`cms-episode${i + 1 === episode ? " is-active" : ""}`}
                onClick={() => changeEpisode(i + 1)}
              >
                {label}
              </button>
            );
          })}
        </div>
      ) : null}
    </section>
  );
}

export default function VideosClient() {
  const [category, setCategory] = useState("all");
  const [items, setItems] = useState<CMSItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [current, setCurrent] = useState<CMSDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);

  const load = useCallback(async (cat: string) => {
    setLoading(true);
    setError(false);
    try {
      const resp = await fetch(`/api/cms/list?category=${cat}&pg=1`);
      if (!resp.ok) throw new Error(String(resp.status));
      const body = (await resp.json()) as { items: CMSItem[] };
      setItems(body.items ?? []);
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load(category);
  }, [category, load]);

  async function openItem(item: CMSItem) {
    setDetailLoading(true);
    setCurrent(null);
    try {
      const resp = await fetch(`/api/cms/detail?id=${encodeURIComponent(item.id)}`);
      if (!resp.ok) throw new Error(String(resp.status));
      const detail = (await resp.json()) as CMSDetail;
      setCurrent(detail);
    } catch {
      setCurrent({ ...item, streamURL: null });
    } finally {
      setDetailLoading(false);
    }
  }

  const visibleItems = useMemo(() => {
    if (category === "all") return items;
    // 后端返回的 category 是原始 type_name（含"短剧/动漫/电影/剧"等），按关键词匹配。
    const target: Record<string, string[]> = {
      movie: ["电影", "片"],
      tv: ["剧", "综艺", "真人秀"],
      drama: ["短剧", "迷你剧"],
      anime: ["动漫", "动画"],
    };
    const keys = target[category] ?? [];
    return items.filter((i) => keys.some((k) => i.category.includes(k)));
  }, [items, category]);

  return (
    <main className="videos-page">
      <section className="tv-hero">
        <div className="container tv-hero__inner">
          <span className="eyebrow">VIDEOS</span>
          <h1>影视库</h1>
          <p>电影、电视剧、短剧与动漫，来自多个公开资源站聚合。</p>
        </div>
      </section>

      <div className="container">
        <div className="videos-cats" role="tablist">
          {CATEGORIES.map((c) => (
            <button
              key={c.key}
              type="button"
              role="tab"
              aria-selected={category === c.key}
              className={`videos-cat${category === c.key ? " is-active" : ""}`}
              onClick={() => setCategory(c.key)}
            >
              {c.label}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="tv-loading">
            <span className="live-spinner" aria-hidden="true" />
            <span>正在载入影视列表…</span>
          </div>
        ) : error ? (
          <div className="tv-error">
            <strong>载入失败</strong>
            <span>请稍后重试</span>
          </div>
        ) : current ? (
          <CmsPlayer detail={current} onClose={() => setCurrent(null)} />
        ) : detailLoading ? (
          <div className="tv-loading">
            <span className="live-spinner" aria-hidden="true" />
            <span>正在解析播放地址…</span>
          </div>
        ) : (
          <div className="tv-station-grid videos-grid">
            {visibleItems.map((item) => (
              <button
                type="button"
                key={`${item.source}-${item.id}`}
                className="tv-station-card"
                onClick={() => openItem(item)}
              >
                <span className="tv-station-logo-wrap">
                  {item.poster ? (
                    <img
                      src={proxiedPoster(item.poster)}
                      alt=""
                      loading="lazy"
                      onError={(e) => {
                        (e.currentTarget as HTMLImageElement).style.display = "none";
                      }}
                    />
                  ) : (
                    <span className="tv-station-fallback">{item.title.slice(0, 2)}</span>
                  )}
                </span>
                <span className="tv-station-info">
                  <strong>{item.title}</strong>
                  <small>
                    {item.category}
                    {item.remarks ? ` · ${item.remarks}` : ""}
                  </small>
                </span>
              </button>
            ))}
            {visibleItems.length === 0 ? (
              <div className="tv-error">
                <span>该分类暂无内容</span>
              </div>
            ) : null}
          </div>
        )}
      </div>
    </main>
  );
}
