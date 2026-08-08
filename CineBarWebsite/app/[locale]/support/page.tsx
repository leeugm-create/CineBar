import type { Metadata } from "next";
import SupportView from "../../support-view";
import { messages, defaultLocale, type Locale } from "../../i18n";

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
  const m = messages[locale as Locale] ?? messages[defaultLocale];
  return { title: m.supportPageTitle, description: m.supportPageNote };
}

export default async function LocaleSupport({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const code = supported.includes(locale as Locale) ? (locale as Locale) : defaultLocale;
  return <SupportView m={messages[code]} locale={code} />;
}