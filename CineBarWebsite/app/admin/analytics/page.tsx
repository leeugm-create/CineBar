import Link from "next/link";
import { headers } from "next/headers";

type Bucket = { value: string | number; installs: number };

type TelemetrySummary = {
  range: string;
  since: string;
  as_of: string;
  total_installs: number;
  active_installs: number;
  by_version: Bucket[];
  by_os_major: Bucket[];
  by_architecture: Bucket[];
  by_language: Bucket[];
};

type SiteStats = {
  total_views: number;
  unique_visitors: number;
  views_7d: number;
  by_path: { path: string; views: number }[];
  by_country: { country: string; views: number }[];
  by_day: { day: string; views: number }[];
  latest: { ts: string; path: string; country: string; locale: string }[];
};

export const dynamic = "force-dynamic";

const telemetryURL =
  process.env.CINEBAR_TELEMETRY_URL ?? "https://telemetry.cinebar.cc";

async function loadSummary(): Promise<TelemetrySummary | null> {
  const token = process.env.CINEBAR_TELEMETRY_ADMIN_TOKEN;
  if (!token) return null;
  try {
    const response = await fetch(
      `${telemetryURL}/v1/telemetry/summary?range=30d`,
      {
        headers: { Authorization: `Bearer ${token}` },
        cache: "no-store",
      },
    );
    if (!response.ok) return null;
    return (await response.json()) as TelemetrySummary;
  } catch {
    return null;
  }
}

async function loadSiteStats(): Promise<SiteStats | null> {
  // 网页统计由 Worker 在渲染前查好 D1 并经 x-cinebar-stats 请求头注入
  //（Worker 禁止 fetch 回自身域名，SSR 无法自调用取 D1）。
  try {
    const raw = (await headers()).get("x-cinebar-stats");
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || parsed.error) return null;
    return parsed as SiteStats;
  } catch {
    return null;
   }
}

function BucketList({ title, rows }: { title: string; rows: Bucket[] }) {
  return (
    <section className="analytics-card">
      <h2>{title}</h2>
      {rows.length === 0 ? (
        <p className="analytics-muted">暂无数据</p>
      ) : (
        <ul className="analytics-list">
          {rows.map((row) => (
            <li key={`${title}-${row.value}`}>
              <span>{row.value}</span>
              <strong>{row.installs}</strong>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

export default async function AnalyticsPage() {
  const summary = await loadSummary();
  const site = await loadSiteStats();
  return (
    <main className="analytics-shell">
      <header className="analytics-header">
        <div>
          <p className="eyebrow">CineBar · 管理员</p>
          <h1>管理后台</h1>
          <p className="analytics-muted">
            网页访问统计与 App 匿名安装统计。IP 仅保存单向哈希，不存原始地址。
          </p>
        </div>
        <Link className="button secondary" href="/">
          返回官网
        </Link>
      </header>

      <h2 className="analytics-section-title">网页访问统计</h2>
      {!site ? (
        <section className="analytics-card analytics-empty">
          <h2>网页统计暂不可用</h2>
          <p>数据尚未建立，或 Worker 未能读入统计。</p>
        </section>
      ) : (
        <>
          <div className="analytics-metrics metrics-3">
            <section className="analytics-card">
              <span className="analytics-label">累计浏览量</span>
              <strong>{site.total_views}</strong>
            </section>
            <section className="analytics-card">
              <span className="analytics-label">近 7 天浏览量</span>
              <strong>{site.views_7d}</strong>
            </section>
            <section className="analytics-card">
              <span className="analytics-label">独立访客</span>
              <strong>{site.unique_visitors}</strong>
            </section>
          </div>
          <div className="analytics-grid">
            <BucketList2 title="热门页面" rows={site.by_path.map((r) => ({ value: r.path, installs: r.views }))} />
            <BucketList2 title="访问地区" rows={site.by_country.map((r) => ({ value: r.country, installs: r.views }))} />
            <BucketList2 title="近 14 天每日访问" rows={site.by_day.map((r) => ({ value: r.day, installs: r.views }))} />
            <section className="analytics-card">
              <h2>最近访问</h2>
              {site.latest.length === 0 ? (
                <p className="analytics-muted">暂无数据</p>
              ) : (
                <ul className="analytics-list">
                  {site.latest.map((r, i) => (
                    <li key={i}>
                      <span>
                        {r.path} · {r.country}
                        <small className="analytics-sub"> {r.locale} · {r.ts}</small>
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          </div>
        </>
      )}

      <h2 className="analytics-section-title">App 匿名安装统计</h2>
      {!summary ? (
        <section className="analytics-card analytics-empty">
          <h2>安装统计暂不可用</h2>
          <p>
            需要管理员运行时凭据，或统计服务暂时没有响应。这个页面不会在浏览器中
            请求或暴露管理员令牌。
          </p>
        </section>
      ) : (
        <>
          <div className="analytics-metrics">
            <section className="analytics-card">
              <span className="analytics-label">累计安装实例</span>
              <strong>{summary.total_installs}</strong>
            </section>
            <section className="analytics-card">
              <span className="analytics-label">近 24 小时活跃</span>
              <strong>{summary.active_installs}</strong>
            </section>
          </div>
          <div className="analytics-grid">
            <BucketList title="版本" rows={summary.by_version} />
            <BucketList title="架构" rows={summary.by_architecture} />
            <BucketList title="macOS 主版本" rows={summary.by_os_major} />
            <BucketList title="界面语言" rows={summary.by_language} />
          </div>
          <p className="analytics-footnote">
            统计区间：{summary.range} · 截止 {summary.as_of}
          </p>
        </>
      )}
    </main>
  );
}

function BucketList2({ title, rows }: { title: string; rows: { value: string | number; installs: number }[] }) {
  return (
    <section className="analytics-card">
      <h2>{title}</h2>
      {rows.length === 0 ? (
        <p className="analytics-muted">暂无数据</p>
      ) : (
        <ul className="analytics-list">
          {rows.map((row, i) => (
            <li key={`${title}-${row.value}-${i}`}>
              <span>{row.value}</span>
              <strong>{row.installs}</strong>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
