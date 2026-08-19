import type { Metadata } from "next";
import WatchClient from "../watch-client";
import SiteHeader from "../site-header";
import { defaultLocale, messages } from "../i18n";

export const metadata: Metadata = {
  title: "在线播放 · CineBar",
  description: "在线影视播放页。",
};

export default function WatchPage() {
  return (
    <main className="site-home tv-page-root watch-zip0">
      <SiteHeader
        locale={defaultLocale}
        appearanceLabel={messages[defaultLocale].appearance}
        homeHref="/"
        navItems={[
          { href: "/", label: "返回官网" },
          { href: "/videos", label: "影视库" },
        ]}
      />
      <WatchClient />
    </main>
  );
}
