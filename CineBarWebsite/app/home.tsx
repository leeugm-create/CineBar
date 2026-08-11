import type { Locale, Messages } from "./i18n";
import LangSelect from "./lang-select";
import SiteSearch from "./site-search";
import ThemeToggle from "./theme-toggle";

const releaseURL =
  "https://cinebar.cc/downloads/CineBar-0.8.3-test-build-64-universal.zip";
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
    <main className="site-home">
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
          <a href="#showcase">{m.navShowcase}</a>
          <a href="#features">{m.navFeatures}</a>
          <a href="#install">{m.navInstall}</a>
          <a href="#support">{m.navSupport}</a>
        </nav>
      </header>

      <section className="hero" id="top">
        <div className="hero-grid">
          <div className="hero-copy">
            <p className="hero-version">{m.heroVersion}</p>
            <div className="hero-title">
              <h1 data-text={`${m.heroTitle1}\n${m.heroTitle2}`}>
                <span className="title-line">{m.heroTitle1}</span>
                <br />
                <span className="title-line">{m.heroTitle2}</span>
              </h1>
            </div>
            <p className="hero-lede">{m.heroLede}</p>
            <p className="hero-note">{m.heroNote}</p>
            <div className="hero-actions">
              <a className="button primary" href={releaseURL}>
                {m.download}
              </a>
              <a className="button link" href="#showcase">
                {m.heroSecondary}
              </a>
            </div>
            <div className="hero-proof" aria-label={m.featuresTitle}>
              {m.features.slice(0, 3).map(([title]) => (
                <span key={title}>{title}</span>
              ))}
            </div>
          </div>
          <div className="hero-visual" aria-label={m.demoHint}>
            <figure className="hero-gif">
              <div className="hero-gif-frame">
                <img src="/cinebar-product-tour.gif" alt={m.demoHint} loading="lazy" />
              </div>
              <figcaption>{m.demoHint}</figcaption>
            </figure>
          </div>
        </div>
        <p className="hero-compat">{m.compat}</p>
      </section>

      <section className="section showcase-section" id="showcase">
        <div className="section-kicker">{m.demoHint}</div>
        <h2>{m.showcaseTitle}</h2>
        <p className="section-lead">{m.showcaseLead}</p>
        <div className="showcase-grid">
          <figure className="showcase-gif">
            <div className="showcase-gif-frame">
              <img src="/cinebar-product-tour.gif" alt={m.demoHint} loading="lazy" />
            </div>
            <figcaption>{m.demoHint}</figcaption>
          </figure>
          <article className="showcase-feature-card">
            <span className="showcase-feature-icon" aria-hidden="true">✦</span>
            <h3>{m.showcaseLibrary}</h3>
            <p>{m.showcaseNote}</p>
            <div className="showcase-feature-pills">
              <span>{m.today}</span>
              <span>{m.watchlist}</span>
              <span>{m.search}</span>
            </div>
          </article>
        </div>
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
        <div className="feature-grid">
          {m.features.slice(0, 3).map(([title, body], index) => (
            <article className="feature-card" key={title}>
              <span className="feature-card-index" aria-hidden="true">0{index + 1}</span>
              <h3>{title}</h3>
              <p>{body}</p>
            </article>
          ))}
        </div>
        <ol className="feature-list feature-list-compact">
          {m.features.slice(3).map(([title, body]) => (
            <li key={title}>
              <span className="feature-title">{title}</span>
              <span className="feature-body">{body}</span>
            </li>
          ))}
        </ol>
      </section>

      <section className="section install-section" id="install">
        <div className="install-panel">
          <div>
            <div className="section-kicker">{m.install}</div>
            <h2>{m.installTitle}</h2>
          </div>
          <ol className="steps">
            {m.steps.map((s, i) => (
              <li key={i}>
                <span className="step-num">{i + 1}</span>
                <p>{s}</p>
              </li>
            ))}
          </ol>
          <p className="install-compat">{m.compat}</p>
        </div>
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
