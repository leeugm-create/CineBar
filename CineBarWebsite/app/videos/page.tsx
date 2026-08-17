import type { Metadata } from "next";
import Link from "next/link";
import VideosClient from "../videos-client";

export const metadata: Metadata = {
  title: "影视库 · CineBar",
  description: "电影、电视剧、短剧与动漫在线观看。",
};

export default function VideosPage() {
  return (
    <main className="site-home tv-page-root">
      <header className="site-header">
        <Link className="brand" href="/">
          <img className="brand-mark" src="/cinebar-icon.png" alt="" width="42" height="42" />
          <span>CineBar</span>
        </Link>
        <nav aria-label="Videos">
          <Link href="/">返回官网</Link>
        </nav>
      </header>

      <VideosClient />
    </main>
  );
}
