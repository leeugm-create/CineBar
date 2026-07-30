import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import "./globals.css";

const title = "CineBar — 今晚看什么？";
const description = "macOS 菜单栏里的电影与电视剧发现工具。";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const rawHost =
    requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  const host = rawHost?.split(",")[0]?.trim() || "cinebar.cc";
  const forwardedProtocol = requestHeaders
    .get("x-forwarded-proto")
    ?.split(",")[0]
    ?.trim();
  const protocol =
    forwardedProtocol === "http" || forwardedProtocol === "https"
      ? forwardedProtocol
      : host.startsWith("localhost")
        ? "http"
        : "https";

  let metadataBase: URL;
  try {
    metadataBase = new URL(`${protocol}://${host}`);
  } catch {
    metadataBase = new URL("https://cinebar.cc");
  }

  return {
    metadataBase,
    title,
    description,
    icons: {
      icon: "/cinebar-icon.png",
      shortcut: "/cinebar-icon.png",
    },
    openGraph: {
      type: "website",
      locale: "zh_CN",
      url: "/",
      siteName: "CineBar",
      title,
      description,
      images: [
        {
          url: "/og.png",
          width: 1200,
          height: 630,
          alt: "CineBar — 今晚看什么？",
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [
        {
          url: "/og.png",
          alt: "CineBar — 今晚看什么？",
        },
      ],
    },
  };
}

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f7f5f1" },
    { media: "(prefers-color-scheme: dark)", color: "#080b20" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
