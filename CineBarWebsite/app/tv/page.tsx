import type { Metadata } from "next";
import Link from "next/link";
import { messages } from "../i18n";
import TVClient from "../tv-client";

export const metadata: Metadata = {
  title: "电视台直播 · CineBar",
  description: "央视、卫视与地方台在线直播。",
};

export default function TVPage() {
  const m = messages["zh-Hans"];
  return (
    <main className="site-home tv-page-root">
      <header className="site-header">
        <Link className="brand" href="/">
          <img className="brand-mark" src="/cinebar-icon.png" alt="" width="42" height="42" />
          <span>CineBar</span>
        </Link>
        <nav aria-label="TV">
          <Link href="/">返回官网</Link>
        </nav>
      </header>

      <TVClient m={m} />
    </main>
  );
}
