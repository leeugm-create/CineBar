"use client";

import { useState } from "react";
import { locales, type Locale } from "./i18n";

export default function LangSelect({ locale }: { locale: Locale }) {
  const [value, setValue] = useState(locale);

  function onChange(next: Locale) {
    setValue(next);
    const entry = locales.find((l) => l.code === next);
    if (!entry) return;
    const here = window.location.pathname;
    let suffix = "";
    let matched = false;
    for (const l of locales) {
      if (here === l.path) {
        suffix = "";
        matched = true;
        break;
      }
      if (here.startsWith(l.path + "/")) {
        suffix = here.slice(l.path.length);
        matched = true;
        break;
      }
    }
    if (!matched) suffix = here;
    window.location.href = `${entry.path}${suffix}`;
  }

  return (
    <label className="lang-select">
      <select
        aria-label="Language"
        value={value}
        onChange={(e) => onChange(e.target.value as Locale)}
      >
        {locales.map((l) => (
          <option key={l.code} value={l.code}>
            {l.label}
          </option>
        ))}
      </select>
    </label>
  );
}