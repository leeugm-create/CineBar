"use client";

import { useEffect, useState } from "react";

const THEME_KEY = "cinebar.theme";

/** 三态主题：light / dark / system（跟随系统，2026-08-18 新增）。 */
type ThemeChoice = "light" | "dark" | "system";

function getStoredTheme(): ThemeChoice | null {
  try {
    const stored = window.localStorage.getItem(THEME_KEY);
    return stored === "light" || stored === "dark" || stored === "system" ? stored : null;
  } catch {
    return null;
  }
}

function systemTheme(): "light" | "dark" {
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function resolveChoice(choice: ThemeChoice): "light" | "dark" {
  return choice === "system" ? systemTheme() : choice;
}

function applyTheme(theme: "light" | "dark") {
  document.documentElement.dataset.theme = theme;
}

const NEXT: Record<ThemeChoice, ThemeChoice> = {
  light: "dark",
  dark: "system",
  system: "light",
};

export default function ThemeToggle({ label }: { label: string }) {
  const [choice, setChoice] = useState<ThemeChoice | null>(null);

  useEffect(() => {
    const stored = getStoredTheme() ?? "system";
    applyTheme(resolveChoice(stored));
    const raf = requestAnimationFrame(() => setChoice(stored));
    return () => cancelAnimationFrame(raf);
  }, []);

  useEffect(() => {
    if (choice) applyTheme(resolveChoice(choice));
  }, [choice]);

  // 跟随系统：系统外观变化时实时切换（仅 system 模式生效）。
  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    function onSystemChange() {
      const current = getStoredTheme() ?? "system";
      if (current === "system") {
        applyTheme(systemTheme());
      }
    }
    mq.addEventListener("change", onSystemChange);
    return () => mq.removeEventListener("change", onSystemChange);
  }, []);

  function cycle() {
    const current = choice ?? getStoredTheme() ?? "system";
    const next = NEXT[current];
    setChoice(next);
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
      onClick={cycle}
      aria-label={label}
      title={label}
    >
      {choice === "system" ? (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="2" />
          <path d="M12 3a9 9 0 0 1 0 18Z" fill="currentColor" />
        </svg>
      ) : choice === "dark" ? (
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
