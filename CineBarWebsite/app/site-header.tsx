"use client";

import { useState } from "react";
import Link from "next/link";
import type { Locale } from "./i18n";
import LangSelect from "./lang-select";
import ThemeToggle from "./theme-toggle";

const GAME_URL = "https://bruno-simon.com";

type NavItem = { href: string; label: string };

/**
 * 全站共用页头：品牌 + 导航 + 语言切换 + 玩玩游戏 + 颜色切换。
 * 移动端（≤840px）导航收进 ☰ 汉堡抽屉，常驻顶栏保留
 * 「语言 → 玩玩游戏 → 颜色」控件条（可在小屏自动折行）。
 */
export default function SiteHeader({
  locale,
  appearanceLabel,
  navItems = [],
  homeHref = "/",
}: {
  locale: Locale;
  appearanceLabel: string;
  navItems?: NavItem[];
  homeHref?: string;
}) {
  const [open, setOpen] = useState(false);
  const close = () => setOpen(false);

  return (
    <header className="site-header">
      <Link className="brand" href={homeHref}>
        <img
          className="brand-mark"
          src="/cinebar-icon.png"
          alt=""
          width="42"
          height="42"
        />
        <span>CineBar</span>
      </Link>

      <div className="header-right">
        <nav className="site-nav" aria-label="Main">
          {navItems.map((n) => (
            <Link key={n.href} href={n.href}>
              {n.label}
            </Link>
          ))}
        </nav>

        <LangSelect locale={locale} />
        <a
          className="play-games-btn"
          href={GAME_URL}
          target="_blank"
          rel="noopener noreferrer"
          title="玩玩游戏（Bruno Simon 3D 作品集）"
        >
          玩玩游戏
        </a>
        <ThemeToggle label={appearanceLabel} />

        <button
          type="button"
          className="menu-toggle"
          aria-label="菜单"
          aria-expanded={open}
          onClick={() => setOpen((v) => !v)}
        >
          <span className="menu-toggle-icon" aria-hidden="true" />
        </button>
      </div>

      {open && (
        <div className="drawer-overlay" onClick={close} aria-hidden="true" />
      )}
      <aside className={`drawer${open ? " is-open" : ""}`} aria-hidden={!open}>
        <nav className="drawer-nav" aria-label="菜单">
          {navItems.map((n) => (
            <Link key={n.href} href={n.href} onClick={close}>
              {n.label}
            </Link>
          ))}
        </nav>
        <a
          className="play-games-btn drawer-game"
          href={GAME_URL}
          target="_blank"
          rel="noopener noreferrer"
          onClick={close}
        >
          玩玩游戏
        </a>
        <button type="button" className="drawer-close" onClick={close} aria-label="关闭菜单">
          关闭
        </button>
      </aside>
    </header>
  );
}