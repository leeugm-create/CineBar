const releaseURL =
  "https://cinebar.cc/downloads/CineBar-0.8.3-test-build-38-universal.zip";
const releasesURL = "https://github.com/leeugm-create/CineBar/releases";

const features = [
  ["发现", "本周热门、每日推荐、即将上映与今日播出。"],
  ["多重评分", "TMDB、IMDb、烂番茄、Metacritic、CineBar 社区与豆瓣评分。"],
  ["完整资料", "演员、剧照、预告片、分级、上映日期与播出时间。"],
  ["片单与提醒", "收藏电影和电视剧，并设置定档、下一集与下一季提醒。"],
  ["本地片库", "分类与状态可组合筛选；确认匹配后打开完整资料，其他文件仅显示本地详情。"],
  ["正版入口", "查看不同地区的合法观看平台。"],
  ["多语言", "支持简体中文、繁体中文、英语、日语与韩语。"],
] as const;

const ratings = ["TMDB", "IMDb", "烂番茄", "Metacritic", "CineBar 社区", "豆瓣"] as const;

function MenubarDemo() {
  return (
    <div className="menubar-demo" aria-label="CineBar 菜单栏交互示意">
      <div className="menubar">
        <span className="menubar-brand">CineBar</span>
        <span className="menubar-time">21:47</span>
      </div>
      <div className="menu-panel">
        <div className="panel-search">找片名、剧名…</div>
        <div className="panel-tabs">
          <span className="panel-tab active">每日推荐</span>
          <span className="panel-tab">本周热门</span>
          <span className="panel-tab">我的片单</span>
        </div>
        <div className="panel-movie">
          <span className="panel-poster" aria-hidden="true" />
          <div className="panel-copy">
            <strong>每日推荐</strong>
            <small>根据你的类型与地区偏好</small>
            <div className="panel-ratings">
              {ratings.map((r) => (
                <span className="rating-badge" key={r}>
                  {r}
                </span>
              ))}
            </div>
          </div>
        </div>
      </div>
      <p className="demo-hint">悬停菜单栏，看它在 mac 上的样子</p>
    </div>
  );
}

export default function Home() {
  return (
    <main>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="CineBar 首页">
          <img
            className="brand-mark"
            src="/cinebar-icon.png"
            alt=""
            width="42"
            height="42"
          />
          <span>CineBar</span>
        </a>
        <nav aria-label="主导航">
          <a href="#features">功能</a>
          <a href="#install">安装</a>
          <a href="#support">支持</a>
        </nav>
      </header>

      <section className="hero" id="top">
        <p className="hero-version">CineBar for macOS · 0.8.3-test.15（Build 38）测试版</p>
        <h1>
          找到
          <br />
          下一部好片
        </h1>
        <p className="hero-lede">
          macOS 菜单栏里的电影与电视剧发现工具。更快找到想看的作品，
          比较评分，查看演员与预告，并把心仪内容加入片单。
        </p>
        <div className="hero-actions">
          <a className="button primary" href={releaseURL}>
            下载 macOS 测试版
          </a>
          <a className="button link" href="#install">
            查看安装说明 →
          </a>
        </div>
        <p className="hero-compat">
          支持 Apple 芯片与 Intel Mac · 免费 · 无广告 · 无订阅
        </p>
        <MenubarDemo />
        <a className="scroll-hint" href="#ratings">
          往下滑 ↓
        </a>
      </section>

      <section className="section" id="ratings">
        <h2>一个片子的分数，一次看全</h2>
        <p className="section-lead">
          TMDB、IMDb、烂番茄、Metacritic、CineBar 社区评分，以及新加入的豆瓣评分，
          全部聚在一处，不一个个网站去翻。
        </p>
        <div className="rating-wall">
          {ratings.map((r) => (
            <span className="rating-badge big" key={r}>
              {r}
            </span>
          ))}
        </div>
        <p className="section-note">
          当前测试版包含豆瓣评分抓取（Build 38）。豆瓣公开页面数据，抓取结果可能因
          风控偶尔缺失，缺失时不影响其他评分展示；简体中文环境预告片已改为豆瓣预告卡片式播放。
        </p>
      </section>

      <section className="section" id="features">
        <h2>找片需要的信息，一处看清</h2>
        <ol className="feature-list">
          {features.map(([title, body]) => (
            <li key={title}>
              <span className="feature-title">{title}</span>
              <span className="feature-body">{body}</span>
            </li>
          ))}
        </ol>
      </section>

      <section className="section" id="install">
        <h2>三步开始使用</h2>
        <ol className="steps">
          <li>
            <span className="step-num">1</span>
            <p>从上方 Build 38 不可变下载地址取得测试包并解压。</p>
          </li>
          <li>
            <span className="step-num">2</span>
            <p>将 CineBar.app 移入“应用程序”文件夹。</p>
          </li>
          <li>
            <span className="step-num">3</span>
            <p>首次启动时右键 CineBar，选择“打开”并确认。</p>
          </li>
        </ol>
      </section>

      <section className="section" id="support">
        <h2>软件保持免费、无广告、无订阅</h2>
        <p className="section-lead">如果 CineBar 为你节省了找片时间，可以自愿支持一次开发。</p>
        <div className="support-grid">
          <a
            className="support-card"
            href="https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&amp;hosted_button_id=VVVZUSU9QUJBW&amp;currency_code=USD"
            target="_blank"
            rel="noreferrer"
          >
            <span className="support-pay-title">PayPal</span>
            <span className="support-pay-desc">美元，用于海外用户</span>
            <span className="support-cta">跳转支付 →</span>
          </a>
          <div className="support-card">
            <span className="support-pay-title">微信</span>
            <img src="/wxpay.png" alt="微信收款码" width="140" height="140" loading="lazy" />
            <span className="support-pay-doc">手机微信扫码打赏</span>
          </div>
          <div className="support-card">
            <span className="support-pay-title">支付宝</span>
            <img src="/alipay.png" alt="支付宝收款码" width="140" height="140" loading="lazy" />
            <span className="support-pay-doc">支付宝扫码打赏</span>
          </div>
        </div>
        <small className="support-note">一次性自愿支持，不会解锁功能，也不是订阅。</small>
      </section>

      <footer>
        <span>© 2026 CineBar</span>
        <a href={releasesURL}>GitHub Releases</a>
      </footer>
    </main>
  );
}
