import type { Metadata } from "next";
import VideosClient from "../videos-client";
import SiteHeader from "../site-header";
import { defaultLocale, messages } from "../i18n";

export const metadata: Metadata = {
  title: "影视库 · CineBar",
  description: "电影、电视剧、短剧与动漫在线观看。",
};

export default function VideosPage() {
  return (
    <main className="site-home tv-page-root">
      <SiteHeader
        locale={defaultLocale}
        appearanceLabel={messages[defaultLocale].appearance}
        homeHref="/"
        navItems={[{ href: "/", label: "返回官网" }]}
      />

      <VideosClient />
    </main>
  );
}
