"use client";

import { useEffect, useRef, useState, type MouseEvent as ReactMouseEvent } from "react";
import type { Locale, Messages } from "./i18n";
import InlinePlayer, { type SearchHit } from "./inline-player";

const HISTORY_KEY = "cinebar.search.history";
const HISTORY_MAX = 8;

function loadHistory(): string[] {
  try {
    const raw = window.localStorage.getItem(HISTORY_KEY);
    const parsed = raw ? (JSON.parse(raw) as unknown) : [];
    return Array.isArray(parsed) ? parsed.filter((x): x is string => typeof x === "string").slice(0, HISTORY_MAX) : [];
  } catch {
    return [];
  }
}

function saveHistory(items: string[]): void {
  try {
    window.localStorage.setItem(HISTORY_KEY, JSON.stringify(items.slice(0, HISTORY_MAX)));
  } catch {
    // private mode or quota exceeded: ignore
  }
}

export default function SiteSearch({ m, locale }: { m: Messages; locale: Locale }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [data, setData] = useState<{ q: string; results: SearchHit[] } | null>(null);
  const [selected, setSelected] = useState<SearchHit | null>(null);
  const [inflight, setInflight] = useState(false);
  const [history, setHistory] = useState<string[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);
  const boxRef = useRef<HTMLDivElement>(null);
  const q = query.trim();
  const eligible = open && q.length >= 2;
  const historyInit = useRef(false);

  useEffect(() => {
    if (open && !historyInit.current) {
      historyInit.current = true;
      setHistory(loadHistory());
    }
  }, [open]);

  useEffect(() => {
    if (open) inputRef.current?.focus();
  }, [open]);

  useEffect(() => {
    function onDown(e: MouseEvent) {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) {
        setOpen(false);
        setSelected(null);
      }
    }
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, []);

  useEffect(() => {
    if (!eligible) return;
    const controller = new AbortController();
    const timer = setTimeout(() => {
      setInflight(true);
      fetch(`/api/search?q=${encodeURIComponent(q)}&locale=${encodeURIComponent(locale)}`, {
        signal: controller.signal,
      })
        .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
        .then((body: { results: SearchHit[] }) => {
          if (!controller.signal.aborted) {
            setData({ q, results: body.results ?? [] });
            if (body.results && body.results.length > 0) {
              setHistory((prev) => {
                const next = [q, ...prev.filter((x) => x !== q)].slice(0, HISTORY_MAX);
                saveHistory(next);
                return next;
              });
            }
          }
        })
        .catch((err: unknown) => {
          if ((err as Error).name !== "AbortError") {
            if (!controller.signal.aborted) setData({ q, results: [] });
          }
        })
        .finally(() => {
          if (!controller.signal.aborted) setInflight(false);
        });
    }, 250);
    return () => {
      clearTimeout(timer);
      controller.abort();
      setInflight(false);
    };
  }, [eligible, q, locale]);

  function clearHistory() {
    setHistory([]);
    saveHistory([]);
  }

  function updateQuery(value: string) {
    setSelected(null);
    setQuery(value);
  }

  const current = data && data.q === q ? data.results : null;
  const loading = eligible && (inflight || (q.length >= 2 && !current && !data?.q));
  const searched = eligible && current !== null;

  function href(r: SearchHit) {
    const slug = r.type === "tv" ? "t" : "m";
    return `https://share.cinebar.cc/${slug}/${r.id}?t=${encodeURIComponent(r.title)}`;
  }

  function activateResult(event: ReactMouseEvent<HTMLAnchorElement>, result: SearchHit) {
    if (typeof window === "undefined") return;
    if (!window.matchMedia("(max-width: 560px)").matches) return;
    event.preventDefault();
    setSelected(result);
  }

  const visible = !current || current.length === 0 ? null : (
    <ul className="search-results">
      {current.map((r) => (
        <li key={`${r.type}${r.id}`}>
          <a href={href(r)} target="_blank" rel="noreferrer" onClick={(event) => activateResult(event, r)}>
            {r.poster ? (
              <img
                className="search-poster"
                src={`https://image.tmdb.org/t/p/w92${r.poster}`}
                alt=""
                width="40"
                height="60"
                loading="lazy"
              />
            ) : (
              <span className="search-poster search-poster-empty" aria-hidden="true" />
            )}
            <span className="search-copy">
              <strong>{r.title}</strong>
              <small>
                {r.type === "movie" ? m.searchMovie : m.searchTV}
                {r.year ? ` · ${r.year.slice(0, 4)}` : ""}
                {r.rating && r.rating > 0 ? ` · ⭐ ${r.rating.toFixed(1)}` : ""}
                <span className={`search-watch-status${r.watch?.length ? " available" : ""}`}>
                  {r.watch?.length ? ` · ${m.playerSource}` : ` · ${m.playerNoSource}`}
                </span>
              </small>
            </span>
          </a>
        </li>
      ))}
    </ul>
  );

  return (
    <div className={`site-search${open ? " open" : ""}`} ref={boxRef}>
      {open ? (
        <>
          <input
            ref={inputRef}
            className="search-input"
            value={query}
            onChange={(e) => updateQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Escape") {
                setOpen(false);
                setSelected(null);
              }
            }}
            placeholder={m.search}
            aria-label={m.search}
            type="search"
          />
          <div className="search-panel">
            {loading && <p className="search-state">{m.searchLoading}</p>}
            {!loading && eligible && searched && current !== null && current.length === 0 && (
              <p className="search-state">{m.searchEmpty}</p>
            )}
            {!loading && !eligible && !searched && query.trim() === "" && history.length > 0 && (
              <div className="search-history">
                <div className="search-history-head">
                  <span>{m.searchHistory}</span>
                  <button type="button" className="search-clear-btn" onClick={clearHistory}>
                    {m.searchClear}
                  </button>
                </div>
                <ul className="search-history-list">
                  {history.map((item) => (
                    <li key={item}>
                      <button type="button" onClick={() => updateQuery(item)}>
                        {item}
                      </button>
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {!loading && !eligible && !searched && query.trim() === "" && history.length === 0 && (
              <p className="search-state">{m.searchNoHistory}</p>
            )}
            {!loading && !eligible && !searched && query.trim() !== "" && (
              <p className="search-state">{m.searchHint}</p>
            )}
            {!loading && eligible && selected && (
              <InlinePlayer key={`${selected.type}-${selected.id}`} hit={selected} m={m} onClose={() => setSelected(null)} />
            )}
            {!loading && eligible && visible}
          </div>
        </>
      ) : (
        <button className="search-toggle" onClick={() => setOpen(true)} aria-label={m.searchOpen}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <circle cx="11" cy="11" r="7" stroke="currentColor" strokeWidth="2" />
            <line x1="16.5" y1="16.5" x2="21" y2="21" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          </svg>
        </button>
      )}
    </div>
  );
}
