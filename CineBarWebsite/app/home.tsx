import type { Locale, Messages } from "./i18n";
import LangSelect from "./lang-select";
import SiteSearch from "./site-search";
import ThemeToggle from "./theme-toggle";

const releaseURL =
  "https://cinebar.cc/downloads/CineBar-0.8.3-test-build-59-universal.zip";
const releasesURL = "https://github.com/leeugm-create/CineBar/releases";

function ratingIcon(id: string) {
  return id === "cinebar" ? "/cinebar-icon.png" : `/ratings/${id}.svg`;
}

function RatingBadge({ id, label, big }: { id: string; label: string; big?: boolean }) {
  return (
    <span className={`rating-badge${big ? " big" : ""}`}>
      <img className="rating-icon" src={ratingIcon(id)} alt="" width="18" height="18" loading="lazy" />
      {label}
    </span>
  );
}

function MenubarDemo({ m }: { m: Messages }) {
  return (
    <div className="menubar-demo" aria-label="CineBar menu bar demo">
      <div className="menubar">
        <span className="menubar-brand">CineBar</span>
        <span className="menubar-time">21:47</span>
      </div>
      <div className="menu-panel">
        <div className="panel-search" aria-hidden="true">
          {m.search}
        </div>
        <div className="panel-tabs">
          <span className="panel-tab active">{m.today}</span>
          <span className="panel-tab">{m.trending}</span>
          <span className="panel-tab">{m.watchlist}</span>
        </div>
        <div className="panel-movie">
          <span className="panel-poster" aria-hidden="true" />
          <div className="panel-copy">
            <strong>{m.dailyRec}</strong>
            <small>{m.dailyBy}</small>
            <div className="panel-ratings">
              {m.ratingSources.map((r) => (
                <RatingBadge key={r.id} id={r.id} label={r.label} />
              ))}
            </div>
          </div>
        </div>
      </div>
      <p className="demo-hint">{m.demoHint}</p>
    </div>
  );
}

function SupportCta({ m, locale }: { m: Messages; locale: Locale }) {
  const supportPath = locale === "zh-Hans" ? "/support" : `/${locale}/support`;
  return (
    <a className="button primary support-cta-btn" href={supportPath}>
      {m.supportAction}
    </a>
  );
}

export default function Home({ m, locale }: { m: Messages; locale: Locale }) {
  return (
    <main>
      <header className="site-header">
        <a className="brand" href={locale === "zh-Hans" ? "/" : `/${locale}`}>
          <img
            className="brand-mark"
            src="/cinebar-icon.png"
            alt=""
            width="42"
            height="42"
          />
          <span>CineBar</span>
        </a>
        <SiteSearch m={m} locale={locale} />
        <LangSelect locale={locale} />
        <ThemeToggle label={m.appearance} />
        <nav aria-label="Main">
          <a href="#features">{m.navFeatures}</a>
          <a href="#install">{m.navInstall}</a>
          <a href="#support">{m.navSupport}</a>
        </nav>
      </header>

      <section className="hero" id="top">
        <p className="hero-version">{m.heroVersion}</p>
        <div className="hero-title">
          <h1 data-text={`${m.heroTitle1}\n${m.heroTitle2}`}>
            <span className="title-line">{m.heroTitle1}</span>
            <br />
            <span className="title-line">{m.heroTitle2}</span>
          </h1>
        </div>
        <p className="hero-lede">{m.heroLede}</p>
        <div className="hero-actions">
          <a className="button primary" href={releaseURL}>
            {m.download}
          </a>
        </div>
        <div className="hero-install" id="install">
          <p className="hero-steps-title">{m.installTitle}</p>
          <ol className="steps">
            {m.steps.map((s, i) => (
              <li key={i}>
                <span className="step-num">{i + 1}</span>
                <p>{s}</p>
              </li>
            ))}
          </ol>
        </div>
        <p className="hero-compat">{m.compat}</p>
        <MenubarDemo m={m} />
      </section>

      <section className="section" id="ratings">
        <h2>{m.ratingsTitle}</h2>
        <p className="section-lead">{m.ratingsLead}</p>
        <div className="rating-wall">
          {m.ratingSources.map((r) => (
            <RatingBadge key={r.id} id={r.id} label={r.label} big />
          ))}
        </div>
      </section>

      <section className="section" id="features">
        <h2>{m.featuresTitle}</h2>
        <ol className="feature-list">
          {m.features.map(([title, body]) => (
            <li key={title}>
              <span className="feature-title">{title}</span>
              <span className="feature-body">{body}</span>
            </li>
          ))}
        </ol>
      </section>

      <section className="section" id="support">
        <h2>{m.supportTitle}</h2>
        <p className="section-lead">{m.supportLead}</p>
        <div className="support-cta-row">
          <SupportCta m={m} locale={locale} />
        </div>
        <small className="support-note">{m.supportNote}</small>
      </section>

      <section className="section" id="contact">
        <h2>{m.contactTitle}</h2>
        <ul className="contact-list">
          {m.contactLinks.map(([label, value, href], i) => (
            <li key={label}>
              <a href={href} target={href.startsWith("mailto:") ? undefined : "_blank"} rel="noreferrer">
                <span className="contact-num">{String(i + 1).padStart(2, "0")}</span>
                <span className="contact-label">{label}</span>
                <span className="contact-value">{value}</span>
                <span className="contact-arrow" aria-hidden="true">↗</span>
              </a>
            </li>
          ))}
        </ul>
      </section>

      <footer>
        <span>© 2026 CineBar</span>
        <a href={releasesURL}>{m.releases}</a>
      </footer>
    </main>
  );
}