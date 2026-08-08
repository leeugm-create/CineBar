import type { Metadata } from "next";
import Home from "../home";
import { messages } from "../i18n";
import type { Locale } from "../i18n";

const supported: Locale[] = ["zh-Hant", "en", "ja", "ko"];

export function generateStaticParams() {
  return supported.map((locale) => ({ locale }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const m = messages[locale as Locale] ?? messages["zh-Hans"];
  return {
    title: m.metaTitle,
    description: m.heroLede,
  };
}

export default async function LocaleHome({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const code = supported.includes(locale as Locale) ? (locale as Locale) : "zh-Hans";
  return <Home m={messages[code]} locale={code} />;
}