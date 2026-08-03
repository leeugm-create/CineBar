import type { Metadata, Viewport } from "next";
import "./globals.css";

const title = "CineBar — 找到下一部好片";
const description = "macOS 菜单栏里的电影与电视剧发现工具。";

export const metadata: Metadata = {
  metadataBase: new URL("https://cinebar.cc"),
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
        alt: "CineBar — 找到下一部好片",
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
        alt: "CineBar — 找到下一部好片",
      },
    ],
  },
};

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
