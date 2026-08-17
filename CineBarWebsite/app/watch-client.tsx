"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Hls from "hls.js";

type SearchResult = {
  source: string;
  sourceName: string;
  id: string;
  title: string;
  year: string;
  poster: string | null;
  category: string;
  episodeCount: number;
  streamURL?: string;
};

function proxiedPoster(raw: string): string {
  return `/api/cms/poster?url=${encodeURIComponent(raw)}`;
}

/** 播放器：对标 zip0，支持选集与换源。 */
function Player({ item, m }: { item: SearchResult; m: string }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [armed, setArmed] = useState(false);
  const [failed, setFailed] = useState(false);
  const [failReason, setFailReason] = useState("");
  const [episode, setEpisode] = useState(1);
  const [alts, setAlts] = useState<{ sourceName: string; url: string }[]>([]);
  const [altIndex, setAltIndex] = useState(-1);
  const [searchingAlt, setSearchingAlt] = useState(false);

  const currentRaw = useMemo(() => {
    if (altIndex >= 0 && alts[altIndex]) return alts[altIndex].url;
    return item.streamURL ?? null;
  }, [altIndex, alts, item.streamURL]);

  async function loadAlternates() {
    setSearchingAlt(true);
    try {
      const resp = await fetch(`/api/cms/search?q=${encodeURIComponent(item.title)}&episode=${episode}`);
      const body = (await resp.json()) as { results?: { sourceName: string; streamURL: string | null }[] };
      const others = (body.results ?? []).filter((r) => r.streamURL).map((r) => ({ sourceName: r.sourceName, url: r.streamURL! }));
      setAlts(others);
      setAltIndex(0);
      setFailed(false);
    } catch { /* 忽略 */ } finally { setSearchingAlt(false); }
  }

  function nextAlt() { setFailed(false); setAltIndex((i) => i + 1); }

  useEffect(() => {
    if (!armed || !currentRaw) return;
    const video = videoRef.current;
    if (!video) return;
    let cancelled = false;
    let hls: Hls | null = null;
    let settled = false;
    const timeout = window.setTimeout(() => {
      if (!settled && !video.currentTime) { settled = true; setFailed(true); setFailReason("加载超时，请换线路"); }
    }, 12000);

    async function resolveAndPlay(raw: string) {
      let src = raw;
      if (!/\.m3u8(\?|$)/i.test(raw)) {
        try {
          const resp = await fetch(`/api/cms/stream?url=${encodeURIComponent(raw)}`);
          const body = (await resp.json()) as { streamURL?: string };
          if (cancelled) return;
          if (body.streamURL) src = body.streamURL;
          else { settled = true; window.clearTimeout(timeout); setFailed(true); setFailReason("无法解析播放地址"); return; }
        } catch { if (cancelled) return; settled = true; window.clearTimeout(timeout); setFailed(true); setFailReason("解析失败"); return; }
      }
      if (cancelled) return;
      if (Hls.isSupported()) {
        hls = new Hls({ maxBufferLength: 60, maxMaxBufferLength: 120, lowLatencyMode: false });
        hls.loadSource(src);
        hls.attachMedia(video);
        hls.on(Hls.Events.ERROR, (_e, data) => { if (data.fatal && !settled) { settled = true; window.clearTimeout(timeout); setFailed(true); setFailReason(`hls错误: ${data.type}/${data.details}`); } });
        hls.on(Hls.Events.MANIFEST_PARSED, () => { window.clearTimeout(timeout); video.play().catch(() => setFailed(true)); });
      } else if (video.canPlayType("application/vnd.apple.mpegurl")) { video.src = src; video.play().catch(() => setFailed(true)); }
      else { setFailed(true); setFailReason("浏览器不支持 m3u8"); }
    }
    resolveAndPlay(currentRaw);
    return () => { cancelled = true; window.clearTimeout(timeout); settled = true; hls?.destroy(); video.removeAttribute("src"); };
  }, [armed, currentRaw]);

  return (
    <section style={{ maxWidth: "900px", margin: "20px auto", padding: "0 16px" }}>
      <h1 style={{ color: "var(--foreground)", fontSize: "22px", marginBottom: "6px" }}>{item.title}</h1>
      <small style={{ color: "var(--muted)" }}>{item.category}{item.year ? ` · ${item.year}` : ""}</small>

      <div style={{ position: "relative", width: "100%", aspectRatio: "16/9", background: "#000", borderRadius: "16px", overflow: "hidden", marginTop: "12px", boxShadow: "0 14px 35px rgba(31,38,71,.15)" }}>
        <video ref={videoRef} controls playsInline style={{ width: "100%", height: "100%", display: "block" }} />
        {!armed || failed ? (
          <div style={{ position: "absolute", inset: 0, background: "var(--background)", backgroundImage: item.poster ? `url("${proxiedPoster(item.poster)}")` : undefined, backgroundSize: "cover", backgroundPosition: "center" }}>
            <div style={{ position: "absolute", inset: 0, background: "rgba(0,0,0,0.6)", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "10px" }}>
              {!failed ? (
                <button type="button" onClick={() => setArmed(true)} style={{ padding: "12px 30px", fontSize: "16px", fontWeight: 700, background: "var(--accent)", color: "var(--accent-ink)", border: "none", borderRadius: "999px", cursor: "pointer" }}>
                  ▶ 播放
                </button>
              ) : (
                <div style={{ color: "#fff", textAlign: "center" }}>
                  <div style={{ color: "#ff6b6b", fontWeight: 700 }}>该片源暂不可播，请换线路</div>
                  {failReason ? <div style={{ fontSize: "12px", marginTop: "6px", color: "#ccc" }}>{failReason}</div> : null}
                  <div style={{ display: "flex", gap: "8px", justifyContent: "center", marginTop: "10px" }}>
                    <button type="button" onClick={loadAlternates} style={{ padding: "6px 16px", background: "var(--accent)", color: "var(--accent-ink)", border: "none", borderRadius: "6px", cursor: "pointer" }}>换线路</button>
                    {alts.length > 0 ? <button type="button" onClick={nextAlt} style={{ padding: "6px 16px", background: "#333", color: "#fff", border: "none", borderRadius: "6px", cursor: "pointer" }}>下一个({alts[altIndex]?.sourceName ?? ""})</button> : null}
                    <button type="button" onClick={() => setArmed(false)} style={{ padding: "6px 16px", background: "#333", color: "#fff", border: "none", borderRadius: "6px", cursor: "pointer" }}>重试</button>
                  </div>
                </div>
              )}
            </div>
          </div>
        ) : null}
      </div>
    </section>
  );
}

export default function WatchClient() {
  const [results, setResults] = useState<SearchResult[]>([]);
  const [current, setCurrent] = useState<SearchResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState("");

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const q = params.get("title") ?? params.get("q") ?? "";
    setQuery(q);
    if (!q) { setLoading(false); return; }
    const ctrl = new AbortController();
    fetch(`/api/cms/search?q=${encodeURIComponent(q)}&episode=1`, { signal: ctrl.signal })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((body: { results?: SearchResult[] }) => {
        const rs = (body.results ?? []).filter((r) => r.title && r.streamURL);
        setResults(rs);
        if (rs.length > 0) {
          const prefer = rs.find((r) => r.source === "lzi" || r.source === "zuid");
          setCurrent(prefer ?? rs[0]);
        }
      })
      .catch(() => {})
      .finally(() => setLoading(false));
    return () => ctrl.abort();
  }, []);

  return (
    <main style={{ minHeight: "60vh" }}>
      {loading ? (
        <p style={{ textAlign: "center", color: "var(--muted)", padding: "60px" }}>正在解析播放地址…</p>
      ) : current ? (
        <Player item={current} m={query} />
      ) : (
        <p style={{ textAlign: "center", color: "var(--muted)", padding: "60px" }}>未找到「{query}」的可播放资源</p>
      )}
    </main>
  );
}
