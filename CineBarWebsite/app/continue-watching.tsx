"use client";

import { useEffect, useState } from "react";
import type { Messages } from "./i18n";
import { listProgress, type WatchProgress } from "./watch-progress";

/** 源站海报一律走 /api/cms/poster 代理（绕防盗链 + 同源 CORS），否则记录里的原始 URL 会加载失败。 */
function proxiedPoster(raw: string): string {
  return `/api/cms/poster?url=${encodeURIComponent(raw)}`;
}

/**
 * 首页「接着上次看」横条（对标 zip0 的 recent-grid）。
 * 读取本地播放进度，点击回到对应影片（网站搜索弹窗由 HomeHero 传入回调）。
 */
export default function ContinueWatching({
  m,
}: {
  m: Messages;
}) {
  // 点击直接进入播放页并续播原进度（2026-08-18 改：原事件机制只传 title 打开搜索弹窗，
  // 播放已迁移到独立 /watch 页，改为带 t 参数跳转，播放器起播后 seek 到原进度）。
  function resume(item: WatchProgress) {
    const params = new URLSearchParams({ title: item.title });
    if (item.year) params.set("year", item.year);
    if (item.currentTime > 0) params.set("t", String(Math.floor(item.currentTime)));
    window.location.href = `/watch?${params.toString()}`;
  }
  const [items, setItems] = useState<WatchProgress[]>(() => {
    if (typeof window === "undefined") return [];
    return listProgress().slice(0, 3);
  });

  useEffect(() => {
    // 监听 storage 事件，其他标签页/搜索弹窗更新进度时同步刷新。
    function onStorage(e: StorageEvent) {
      if (e.key === "cinebar.watch.progress") {
        setItems(listProgress().slice(0, 3));
      }
    }
    // bfcache 恢复（浏览器后退/前进返回首页）不会重新挂载组件，也不会触发 storage 事件，
    // 必须在 pageshow(persisted) 时强制重新读取本地进度（2026-08-18 修复：返回首页看不到新记录）。
    function onPageShow(e: PageTransitionEvent) {
      if (e.persisted) {
        setItems(listProgress().slice(0, 3));
      }
    }
    window.addEventListener("storage", onStorage);
    window.addEventListener("pageshow", onPageShow);
    return () => {
      window.removeEventListener("storage", onStorage);
      window.removeEventListener("pageshow", onPageShow);
    };
  }, []);

  if (items.length === 0) return null;

  function percent(item: WatchProgress): number {
    if (!item.duration || item.duration <= 0) return 0;
    return Math.min(Math.max((item.currentTime / item.duration) * 100, 0), 100);
  }

  function fmtTime(seconds: number): string {
    if (!Number.isFinite(seconds) || seconds < 0) return "0:00";
    const total = Math.floor(seconds);
    const h = Math.floor(total / 3600);
    const min = Math.floor((total % 3600) / 60);
    const sec = total % 60;
    if (h > 0) return `${h}:${String(min).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
    return `${min}:${String(sec).padStart(2, "0")}`;
  }

  function fmtLeft(item: WatchProgress): string {
    const left = Math.max(item.duration - item.currentTime, 0);
    return `${m.watchLeft} ${fmtTime(left)}`;
  }

  return (
    <section className="continue-watching section container" aria-label={m.watchContinue}>
      <div className="section-heading continue-watching__heading">
        <div>
          <span className="eyebrow">{m.watchContinueEyebrow}</span>
          <h2>{m.watchContinue}</h2>
        </div>
        <span className="section-heading__aside">{m.watchLocalNote}</span>
      </div>
      <div className="continue-watching__grid">
        {items.map((item) => (
          <button
            type="button"
            key={item.key}
            className="continue-card"
            onClick={() => resume(item)}
          >
            <span className="continue-card__poster">
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
                <span className="continue-card__poster-empty" aria-hidden="true" />
              )}
              <span className="continue-card__play" aria-hidden="true">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M8 5v14l11-7z" />
                </svg>
              </span>
              <span className="progress-track" aria-hidden="true">
                <i style={{ width: `${percent(item)}%` }} />
              </span>
            </span>
            <span className="continue-card__body">
              <strong>{item.title}</strong>
              <span>
                {item.type === "movie" ? m.searchMovie : m.searchTV}
                {item.year ? ` · ${item.year.slice(0, 4)}` : ""}
                {item.sourceLabel ? ` · ${item.sourceLabel}` : ""}
              </span>
              <small>{fmtLeft(item)}</small>
            </span>
          </button>
        ))}
      </div>
    </section>
  );
}
