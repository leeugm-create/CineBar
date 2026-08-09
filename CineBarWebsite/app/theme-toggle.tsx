"use client";

import { useEffect, useState } from "react";

const THEME_KEY = "cinebar.theme";

function getStoredTheme(): "light" | "dark" | null {
  try {
    const stored = window.localStorage.getItem(THEME_KEY);
    return stored === "light" || stored === "dark" ? stored : null;
  } catch {
    return null;
  }
}

function systemTheme(): "light" | "dark" {
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

export default function ThemeToggle({ label }: { label: string }) {
  const [theme, setTheme] = useState<"light" | "dark" | null>(null);

  useEffect(() => {
    const resolved = getStoredTheme() ?? systemTheme();
    applyTheme(resolved);
    const raf = requestAnimationFrame(() => setTheme(resolved));
    return () => cancelAnimationFrame(raf);
  }, []);

  useEffect(() => {
    if (theme) applyTheme(theme);
  }, [theme]);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    function onSystemChange() {
      if (!getStoredTheme()) {
        const next = systemTheme();
        applyTheme(next);
        setTheme(next);
      }
    }
    mq.addEventListener("change", onSystemChange);
    return () => mq.removeEventListener("change", onSystemChange);
  }, []);

  function toggle() {
    const next: "light" | "dark" = theme !== "dark" ? "dark" : "light";
    setTheme(next);
    try {
      window.localStorage.setItem(THEME_KEY, next);
    } catch {
      // private mode: session-only
    }
  }

  return (
    <button
      type="button"
      className="theme-toggle"
      onClick={toggle}
      aria-label={label}
      title={label}
    >
      {theme === "dark" ? (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <circle cx="12" cy="12" r="4.5" stroke="currentColor" strokeWidth="2" />
          <line x1="12" y1="2.5" x2="12" y2="5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          <line x1="12" y1="19" x2="12" y2="21.5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          <line x1="2.5" y1="12" x2="5" y2="12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          <line x1="19" y1="12" x2="21.5" y2="12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          <line x1="4.9" y1="4.9" x2="6.7" y2="6.7" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          <line x1="17.3" y1="17.3" x2="19.1" y2="19.1" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          <line x1="19.1" y1="4.9" x2="17.3" y2="6.7" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          <line x1="6.7" y1="17.3" x2="4.9" y2="19.1" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
        </svg>
      ) : (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <path
            d="M21 12.8A9 9 0 1 1 11.2 3 7 7 0 0 0 21 12.8Z"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinejoin="round"
          />
        </svg>
      )}
    </button>
  );
}

function applyTheme(theme: "light" | "dark") {
  document.documentElement.dataset.theme = theme;
}