import type { Metadata } from "next";
import SupportView from "../support-view";
import { messages } from "../i18n";

export const metadata: Metadata = {
  title: messages["zh-Hans"].supportPageTitle,
  description: messages["zh-Hans"].supportPageNote,
};

export default function SupportPage() {
  return <SupportView m={messages["zh-Hans"]} locale="zh-Hans" />;
}