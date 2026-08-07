const releaseURL =
  "https://cinebar.cc/downloads/CineBar-0.8.3-test-build-37-universal.zip";
const releasesURL = "https://github.com/leeugm-create/CineBar/releases";

const features = [
  ["发现", "本周热门、每日推荐、即将上映与今日播出。"],
  ["多重评分", "TMDB、IMDb、烂番茄、Metacritic 与 CineBar 社区评分。"],
  ["完整资料", "演员、剧照、预告片、分级、上映日期与播出时间。"],
  ["片单与提醒", "收藏电影和电视剧，并设置定档、下一集与下一季提醒。"],
  ["本地片库", "分类与状态可组合筛选；确认匹配后打开完整资料，其他文件仅显示本地详情。"],
  ["正版入口", "查看不同地区的合法观看平台。"],
  ["多语言", "支持简体中文、繁体中文、英语、日语与韩语。"],
] as const;

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
          <a href="#privacy">隐私</a>
          <a href="#support">支持</a>
        </nav>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">CineBar for macOS · 0.8.3-test.15（Build 37）测试版</p>
          <h1>找到下一部好片</h1>
          <p className="lede">
            macOS 菜单栏里的电影与电视剧发现工具。更快找到想看的作品，
            比较评分，查看演员与预告，并把心仪内容加入片单。
          </p>
          <div className="actions">
            <a className="button primary" href={releaseURL}>
              下载 macOS 测试版
            </a>
            <a className="button secondary" href="#install">
              查看安装说明
            </a>
          </div>
          <p className="compatibility">
            支持 Apple 芯片与 Intel Mac · 免费 · 无广告 · 无订阅
          </p>
          <p className="compatibility">
            当前测试包不是正式稳定版。Build 37 已发布签名 appcast，可在 CineBar
            应用内检查、下载并安装，也可使用上方不可变地址直接下载。
          </p>
        </div>
        <div className="product-card" aria-label="CineBar 产品界面示意">
          <div className="product-toolbar">
            <span>电影</span>
            <span>电视剧</span>
            <span>我的片单</span>
          </div>
          <div className="recommendation">
            <span className="poster" aria-hidden="true" />
            <div>
              <small>每日推荐</small>
              <strong>根据你的类型与地区偏好</strong>
              <p>评分、演员、剧照、预告和正版观看入口集中呈现。</p>
            </div>
          </div>
        </div>
      </section>

      <section className="section" id="features">
        <p className="section-label">核心功能</p>
        <h2>找片需要的信息，一处看清</h2>
        <div className="feature-grid">
          {features.map(([title, body]) => (
            <article key={title}>
              <h3>{title}</h3>
              <p>{body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="section split" id="install">
        <div>
          <p className="section-label">安装</p>
          <h2>三步开始使用</h2>
        </div>
        <ol>
          <li>从上方 Build 37 不可变下载地址取得测试包并解压。</li>
          <li>将 CineBar.app 移入“应用程序”文件夹。</li>
          <li>首次启动时右键 CineBar，选择“打开”并确认。</li>
        </ol>
        <p className="notice">
          当前测试包尚未经过 Apple Developer ID 签名与公证。只从官网入口或
          GitHub Releases 下载；用户无需部署 Cloudflare、安装 Node.js 或申请 API
          Key。
        </p>
        <p className="notice">
          安装前请验证 CineBar 独立签名；独立签名不等于 Apple 公证。
        </p>
      </section>

      <section className="section split" id="privacy">
        <div>
          <p className="section-label">隐私与数据</p>
          <h2>不用账号，也不靠跟踪换取免费</h2>
        </div>
        <div>
          <p>片单和推荐偏好默认保存在本机。CineBar 不出售个人数据。</p>
          <p>
            社区评分使用仅保存在本机偏好中的匿名设备标识；服务端只保存其哈希，
            每个作品仅可评分一次。
          </p>
          <p>
            为估算测试版装机规模，应用每天最多发送一次匿名启动统计：版本、Build、
            macOS 主版本、CPU 架构和界面语言。服务端只保存 HMAC 哈希后的安装标识和
            汇总字段，不保存原始标识、IP、文件名、影片内容或账号；当前测试版没有关闭
            统计的设置入口。
          </p>
          <p>
            影片资料来自 TMDB，IMDb、烂番茄与 Metacritic 评分经 OMDb 提供，
            电视剧播出时间由 TVMaze 补充。CineBar 不提供盗版片源或非法下载。
          </p>
        </div>
      </section>

      <section className="section support" id="support">
        <p className="section-label">支持 CineBar</p>
        <h2>软件保持免费、无广告、无订阅</h2>
        <p>如果 CineBar 为你节省了找片时间，可以自愿支持一次开发。</p>
        <form action="https://www.paypal.com/cgi-bin/webscr" method="post">
          <input type="hidden" name="cmd" value="_s-xclick" />
          <input type="hidden" name="hosted_button_id" value="VVVZUSU9QUJBW" />
          <input type="hidden" name="currency_code" value="USD" />
          <button className="button secondary" type="submit">
            用 PayPal 自愿支持 5 美元
          </button>
        </form>
        <small>一次性自愿支持，不会解锁功能，也不是订阅。</small>
      </section>

      <footer>
        <span>© 2026 CineBar</span>
        <a href={releasesURL}>GitHub Releases</a>
        <a href="https://share.cinebar.cc/health">服务状态</a>
      </footer>
    </main>
  );
}
