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
  return (
    <main className="analytics-shell">
      <header className="analytics-header">
        <div>
          <p className="eyebrow">CineBar · 管理员</p>
          <h1>匿名安装统计</h1>
          <p className="analytics-muted">
            只显示汇总数量，不显示安装编号、IP、文件名或用户账号。
          </p>
        </div>
        <a className="button secondary" href="/">
          返回官网
        </a>
      </header>
      {!summary ? (
        <section className="analytics-card analytics-empty">
          <h2>统计页暂不可用</h2>
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
