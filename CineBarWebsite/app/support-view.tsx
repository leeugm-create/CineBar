import Link from "next/link";
import type { Locale, Messages } from "./i18n";
import LangSelect from "./lang-select";

const paypalURL =
  "https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=VVVZUSU9QUJBW&currency_code=USD";

export default function SupportView({ m, locale }: { m: Messages; locale: Locale }) {
  const homePath = locale === "zh-Hans" ? "/" : `/${locale}`;
  return (
    <main>
      <header className="site-header">
        <a className="brand" href={homePath}>
          <img
            className="brand-mark"
            src="/cinebar-icon.png"
            alt=""
            width="42"
            height="42"
          />
          <span>CineBar</span>
        </a>
        <LangSelect locale={locale} />
        <nav aria-label="Support">
          <Link href={homePath}>{m.backHome}</Link>
        </nav>
      </header>

      <section className="section support-page">
        <h2>{m.supportPageTitle}</h2>
        <p className="section-lead">{m.supportPageNote}</p>
        <p className="section-lead">{m.supportLead}</p>
        <div className="support-grid">
          <a className="support-card" href={paypalURL} target="_blank" rel="noreferrer">
            <span className="support-pay-title">{m.paypal}</span>
            <span className="support-pay-desc">{m.paypalDesc}</span>
            <span className="support-cta">{m.payNow}</span>
          </a>
          <div className="support-card">
            <span className="support-pay-title">{m.wechat}</span>
            <img src="/wxpay.png" alt={m.wechat} width="140" height="140" loading="lazy" />
            <span className="support-pay-doc">{m.wechatDoc}</span>
          </div>
          <div className="support-card">
            <span className="support-pay-title">{m.alipay}</span>
            <img src="/alipay.png" alt={m.alipay} width="140" height="140" loading="lazy" />
            <span className="support-pay-doc">{m.alipayDoc}</span>
          </div>
        </div>
        <small className="support-note">{m.supportNote}</small>
      </section>

      <footer>
        <span>© 2026 CineBar</span>
        <a href={homePath}>{m.backHome}</a>
      </footer>
    </main>
  );
}