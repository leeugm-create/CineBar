import type { Metadata } from "next";
import Link from "next/link";
import WatchClient from "../watch-client";

export const metadata: Metadata = {
  title: "在线播放 · CineBar",
  description: "在线影视播放页。",
};

export default function WatchPage() {
  return (
    <main className="site-home tv-page-root watch-zip0">
      <header className="site-header">
        <Link className="brand" href="/">
          <img className="brand-mark" src="/cinebar-icon.png" alt="" width="42" height="42" />
          <span>CineBar</span>
        </Link>
        <nav aria-label="Watch">
          <Link href="/">返回官网</Link>
          <Link href="/videos">影视库</Link>
        </nav>
      </header>
      <WatchClient />
    </main>
  );
}
