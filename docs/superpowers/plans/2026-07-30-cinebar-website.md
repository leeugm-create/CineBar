# CineBar Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a concise, accessible CineBar product website at `https://cinebar.cc` without changing the existing movie, television, API, community-rating, or Build 16 share behavior.

**Architecture:** Build a dedicated single-page Sites project in `CineBarWebsite`, deploy and validate it on its Sites production URL, then move only the `cinebar.cc` apex hostname from the Share Worker to the Site. Keep `share.cinebar.cc`, `api.cinebar.cc`, and `community.cinebar.cc` on their current Workers.

**Tech Stack:** Sites vinext starter, React, TypeScript, CSS media queries, Node test runner, Cloudflare/Sites hosting, GitHub Releases.

## Global Constraints

- The canonical public hostname is exactly `cinebar.cc`.
- The primary download link is exactly `https://github.com/leeugm-create/CineBar/releases`.
- The site must identify the current build as a test version, not a stable release.
- The site must follow `prefers-color-scheme` without requiring JavaScript.
- The site must respect `prefers-reduced-motion`.
- The site must not claim Apple Developer ID signing or notarization.
- The site must state that CineBar is free, has no ads, and has no subscriptions.
- Existing `/m/<ID>`, `/t/<ID>`, `/updates/latest.json`, and `/health` behavior on `share.cinebar.cc` must remain unchanged.
- Existing client endpoints `api.cinebar.cc`, `community.cinebar.cc`, and `share.cinebar.cc` must remain unchanged.
- Build 16 application code and packages must not be rebuilt or modified by the website tasks.

---

## File Structure

- `CineBarWebsite/app/page.tsx`: product page content and semantic section structure.
- `CineBarWebsite/app/layout.tsx`: title, description, favicon, theme-color, and social metadata.
- `CineBarWebsite/app/globals.css`: light/dark tokens, responsive layout, accessibility, and reduced-motion behavior.
- `CineBarWebsite/app/health/route.ts`: independent website health response.
- `CineBarWebsite/public/cinebar-icon.png`: existing CineBar application icon copied without modification.
- `CineBarWebsite/public/og.png`: one validated social-preview image generated from the finished visual system.
- `CineBarWebsite/tests/content.test.mjs`: source-level assertions for required copy, links, and theme media queries.
- `CineBarWebsite/.openai/hosting.json`: opaque Sites project ID only.
- `CineBarShare/wrangler.jsonc`: remove only the `cinebar.cc` apex route after the new Site is already deployed and validated.
- `CineBarShare/tests/share-worker.test.mjs`: regression assertion that the Share Worker still owns its service hostname and existing routes.

### Task 1: Initialize the Dedicated Website and Lock Required Content

**Files:**
- Create: `CineBarWebsite/app/page.tsx`
- Create: `CineBarWebsite/app/layout.tsx`
- Create: `CineBarWebsite/app/globals.css`
- Create: `CineBarWebsite/tests/content.test.mjs`
- Create: `CineBarWebsite/.openai/hosting.json`
- Copy: `CineBar/Assets/CineBar-icon-1024.png` to `CineBarWebsite/public/cinebar-icon.png`

**Interfaces:**
- Consumes: the approved product copy and GitHub Releases URL.
- Produces: a buildable Sites project with stable DOM section IDs `features`, `install`, `privacy`, and `support`.

- [ ] **Step 1: Initialize the Sites project**

Run the Sites initializer exactly once with `CineBarWebsite` as its target:

```bash
mkdir -p CineBarWebsite
/Users/bruce/.codex/plugins/cache/openai-bundled/sites/0.1.31/scripts/init-site.sh \
  "$PWD/CineBarWebsite"
```

Expected: the project contains `app/page.tsx`, `app/layout.tsx`,
`app/globals.css`, `package.json`, and `.openai/hosting.json`.

- [ ] **Step 2: Start the retained local preview**

Run `npm run dev` in `CineBarWebsite` as a retained session, use the exact Local
URL printed by the healthy server, and open that URL once in the in-app browser.
Keep the server running through the production build and hosting steps.

- [ ] **Step 3: Write the failing source-content test**

Create `CineBarWebsite/tests/content.test.mjs`:

```js
import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("publishes the approved CineBar identity and download entry", async () => {
  const page = await read("app/page.tsx");
  assert.match(page, /今晚看什么？/);
  assert.match(page, /macOS 菜单栏/);
  assert.match(page, /测试版/);
  assert.match(
    page,
    /https:\/\/github\.com\/leeugm-create\/CineBar\/releases/,
  );
  assert.match(page, /免费/);
  assert.match(page, /无广告/);
  assert.match(page, /无订阅/);
  assert.match(page, /https:\/\/www\.paypal\.com\/cgi-bin\/webscr/);
  assert.match(page, /VVVZUSU9QUJBW/);
});

test("contains accessible navigation and all required sections", async () => {
  const page = await read("app/page.tsx");
  for (const id of ["features", "install", "privacy", "support"]) {
    assert.match(page, new RegExp(`id=["']${id}["']`));
  }
  assert.match(page, /aria-label=["']主导航["']/);
  assert.match(page, /Apple 芯片与 Intel Mac/);
  assert.match(page, /右键/);
  assert.match(page, /TMDB/);
  assert.match(page, /OMDb/);
});

test("follows system appearance and reduced-motion preferences", async () => {
  const css = await read("app/globals.css");
  assert.match(css, /prefers-color-scheme:\s*dark/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /--background:/);
  assert.match(css, /--foreground:/);
});
```

- [ ] **Step 4: Run the test to verify it fails**

Run:

```bash
cd CineBarWebsite
node --test tests/content.test.mjs
```

Expected: FAIL because the starter does not contain the approved CineBar copy.

- [ ] **Step 5: Replace the starter with the semantic product page**

Implement `app/page.tsx` with:

```tsx
const releaseURL = "https://github.com/leeugm-create/CineBar/releases";

const features = [
  ["发现", "本周热门、每日推荐、即将上映与今日播出。"],
  ["多重评分", "TMDB、IMDb、烂番茄、Metacritic 与 CineBar 社区评分。"],
  ["完整资料", "演员、剧照、预告片、分级、上映日期与播出时间。"],
  ["片单与提醒", "收藏电影和电视剧，并设置定档、下一集与下一季提醒。"],
  ["正版入口", "查看不同地区的合法观看平台。"],
  ["多语言", "支持简体中文、繁体中文、英语、日语与韩语。"],
] as const;

export default function Home() {
  return (
    <main>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="CineBar 首页">
          <img src="/cinebar-icon.png" alt="" width="42" height="42" />
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
          <p className="eyebrow">CineBar for macOS · 当前为测试版</p>
          <h1>今晚看什么？</h1>
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
        </div>
        <div className="product-card" aria-label="CineBar 产品界面示意">
          <div className="product-toolbar">
            <span>电影</span><span>电视剧</span><span>我的片单</span>
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
            <article key={title}><h3>{title}</h3><p>{body}</p></article>
          ))}
        </div>
      </section>

      <section className="section split" id="install">
        <div><p className="section-label">安装</p><h2>三步开始使用</h2></div>
        <ol>
          <li>从 CineBar GitHub Releases 下载最新测试包并解压。</li>
          <li>将 CineBar.app 移入“应用程序”文件夹。</li>
          <li>首次启动时右键 CineBar，选择“打开”并确认。</li>
        </ol>
        <p className="notice">
          当前测试包尚未经过 Apple Developer ID 签名与公证。只从官网入口或
          GitHub Releases 下载；用户无需部署 Cloudflare、安装 Node.js 或申请 API Key。
        </p>
      </section>

      <section className="section split" id="privacy">
        <div><p className="section-label">隐私与数据</p><h2>不用账号，也不靠跟踪换取免费</h2></div>
        <div>
          <p>片单和推荐偏好默认保存在本机。CineBar 不出售个人数据。</p>
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
        <a href={releaseURL}>GitHub Releases</a>
        <a href="https://share.cinebar.cc/health">服务状态</a>
      </footer>
    </main>
  );
}
```

Remove `app/_sites-preview` and its imports. Remove
`react-loading-skeleton` if no other file imports it, then refresh the lockfile.

- [ ] **Step 6: Add accessible light and dark visual tokens**

Replace `app/globals.css` with a finished stylesheet that defines:

```css
:root {
  color-scheme: light dark;
  --background: #f7f5f1;
  --surface: rgba(255, 255, 255, 0.82);
  --foreground: #10162f;
  --muted: #5d6479;
  --border: rgba(16, 22, 47, 0.12);
  --accent: #e87919;
  --accent-ink: #1b1208;
  --shadow: 0 24px 70px rgba(31, 38, 71, 0.12);
}

@media (prefers-color-scheme: dark) {
  :root {
    --background: #080b20;
    --surface: rgba(18, 24, 55, 0.84);
    --foreground: #f7f8ff;
    --muted: #adb5d0;
    --border: rgba(255, 255, 255, 0.14);
    --accent: #ffad4d;
    --accent-ink: #211303;
    --shadow: 0 28px 90px rgba(0, 0, 0, 0.34);
  }
}

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    scroll-behavior: auto !important;
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

Complete the stylesheet with:

- a centered `max-width: 1180px` page;
- a sticky but non-obscuring header;
- a `.brand-mark` and all interface icons whose foreground, backing, border,
  and shadow use the current light/dark CSS variables instead of fixed colors;
- 44-pixel minimum action height;
- a two-column hero above 840 pixels and one column below it;
- six feature cards with readable non-transparent text surfaces;
- visible keyboard focus rings using `outline: 3px solid var(--accent)`;
- no horizontal overflow at 320 CSS pixels;
- body text line height of at least `1.65`.

- [ ] **Step 7: Set finished metadata and icon**

Implement `app/layout.tsx` with the title `CineBar — 今晚看什么？`, the
description `macOS 菜单栏里的电影与电视剧发现工具。`, icon
`/cinebar-icon.png`, and light/dark theme-color metadata. Remove the starter
`codex-preview` marker.

Copy the existing icon:

```bash
cp ../CineBar/Assets/CineBar-icon-1024.png public/cinebar-icon.png
```

- [ ] **Step 8: Run the content test**

Run:

```bash
node --test tests/content.test.mjs
```

Expected: all three tests PASS.

- [ ] **Step 9: Commit**

```bash
git add CineBarWebsite
git commit -m "feat: build CineBar product website"
```

### Task 2: Add Health Response, Build Validation, and Social Preview

**Files:**
- Create: `CineBarWebsite/app/health/route.ts`
- Create: `CineBarWebsite/public/og.png`
- Modify: `CineBarWebsite/app/layout.tsx`
- Modify: `CineBarWebsite/tests/content.test.mjs`

**Interfaces:**
- Consumes: the stable page palette, headline, and content from Task 1.
- Produces: `GET /health` JSON and one finished Open Graph image.

- [ ] **Step 1: Write the failing health-source test**

Append:

```js
test("exposes an uncached website health response", async () => {
  const route = await read("app/health/route.ts");
  assert.match(route, /service:\s*["']cinebar-website["']/);
  assert.match(route, /cache-control/);
  assert.match(route, /no-store/);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run `node --test tests/content.test.mjs`.

Expected: FAIL because `app/health/route.ts` does not exist.

- [ ] **Step 3: Implement the health route**

Create `app/health/route.ts`:

```ts
export function GET() {
  return Response.json(
    {
      ok: true,
      service: "cinebar-website",
      version: "0.8.2-test",
      utc: new Date().toISOString(),
    },
    {
      headers: {
        "cache-control": "no-store",
        "x-content-type-options": "nosniff",
      },
    },
  );
}
```

- [ ] **Step 4: Generate exactly one social preview**

Use ImageGen once with a landscape prompt containing:

```text
Create a finished 1200x630 social preview for CineBar, a macOS menu-bar movie
and television discovery app. Use the finished website's deep navy, warm ivory,
and orange palette. Include the CineBar ticket/play icon, the exact Chinese
headline “今晚看什么？” and the exact supporting line “CineBar for macOS”.
Keep the design minimal, high contrast, and legible at small sizes. Do not add
ratings, awards, download counts, or invented interface text.
```

Inspect the result once. If the two required text strings are wrong or
unreadable, retry once with the same strings emphasized. Save the accepted
image as `public/og.png`.

- [ ] **Step 5: Wire absolute social metadata**

Update `app/layout.tsx` to emit Open Graph and X metadata for `/og.png`, with the
absolute base derived from the incoming host as supported by the Sites starter.
Do not ship an image URL if the generated card failed text validation.

- [ ] **Step 6: Run tests and production build**

Run:

```bash
node --test tests/content.test.mjs
npm run build
```

Expected: tests PASS and the build completes successfully.

- [ ] **Step 7: Commit**

```bash
git add CineBarWebsite
git commit -m "feat: add CineBar website health and social metadata"
```

### Task 3: Publish the Site Before Moving the Apex Domain

**Files:**
- Modify: `CineBarWebsite/.openai/hosting.json`

**Interfaces:**
- Consumes: the exact successful build and commit SHA from Task 2.
- Produces: a saved, deployed Sites version with a production Sites URL.

- [ ] **Step 1: Read hosting metadata**

Verify whether `.openai/hosting.json` has a `project_id`. Do not invent or
transform this value.

- [ ] **Step 2: Create the Site once**

If no `project_id` exists, create one Site with:

- title: `CineBar`
- slug: `cinebar-official`
- description: `CineBar for macOS 官方产品网站`

Persist the returned opaque ID unchanged in `.openai/hosting.json`.

- [ ] **Step 3: Push the exact validated source**

Push the committed Task 2 source with the short-lived Sites credential. Use the
branch-head SHA as `commit_sha`; never put the token into a remote URL or Git
configuration.

- [ ] **Step 4: Package and save the exact version**

Run the Sites `package-site.sh` helper against `CineBarWebsite`, save one
version using the Task 2 `commit_sha`, and deploy it privately when the
connector confirms owner-only access. If only public deployment is available,
obtain explicit approval before publishing.

- [ ] **Step 5: Verify the Sites production URL**

Set `deployed_url` to the exact production URL returned by Sites, then verify:

```bash
curl -fsS "$deployed_url/" | grep -F "今晚看什么？"
curl -fsS "$deployed_url/health" | grep -F '"cinebar-website"'
```

Expected: both requests succeed.

### Task 4: Move Only `cinebar.cc` and Preserve Share Worker Behavior

**Files:**
- Modify: `CineBarShare/wrangler.jsonc`
- Modify: `CineBarShare/tests/share-worker.test.mjs`
- Modify: `CineBarWebsite/.openai/hosting.json`

**Interfaces:**
- Consumes: the verified Site project ID and exact custom-domain validation records.
- Produces: `cinebar.cc` serving the Site while `share.cinebar.cc` continues serving Build 16 share and update routes.

- [ ] **Step 1: Add a failing configuration regression**

Append a test that reads `CineBarShare/wrangler.jsonc`, removes comments, parses
it, and asserts:

```js
import { readFile } from "node:fs/promises";

const configSource = await readFile(
  new URL("../wrangler.jsonc", import.meta.url),
  "utf8",
);
const config = JSON.parse(
  configSource
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, ""),
);
assert.deepEqual(config.routes, [
  { pattern: "share.cinebar.cc", custom_domain: true },
]);
```

- [ ] **Step 2: Run the Share Worker tests to verify the new assertion fails**

Run:

```bash
cd CineBarShare
node --test tests/share-worker.test.mjs
```

Expected: FAIL because `cinebar.cc` is still attached to the Share Worker.

- [ ] **Step 3: Remove only the apex route**

Change `CineBarShare/wrangler.jsonc` routes to:

```json
"routes": [
  { "pattern": "share.cinebar.cc", "custom_domain": true }
]
```

Do not change the Worker name, secret, download URL, or code.

- [ ] **Step 4: Run Share Worker tests**

Run:

```bash
node --test tests/share-worker.test.mjs
```

Expected: all tests PASS.

- [ ] **Step 5: Deploy the reduced Share Worker route**

Deploy the current Share Worker and immediately verify:

```bash
curl -fsS https://share.cinebar.cc/health
curl -fsS https://share.cinebar.cc/updates/latest.json
curl -fsS https://share.cinebar.cc/m/603 | grep -F "CineBar"
curl -fsS https://share.cinebar.cc/t/1399 | grep -F "CineBar"
```

Expected: all four requests succeed before changing apex DNS.

- [ ] **Step 6: Attach `cinebar.cc` to the Site**

Use the exact Site project ID to add custom hostname `cinebar.cc`. Apply only
the A/validation records returned by Sites. Remove conflicting apex records
only after recording them for rollback.

- [ ] **Step 7: Refresh domain status and verify production**

Refresh until the custom domain reports active, then verify:

```bash
curl -I http://cinebar.cc/
curl -fsS https://cinebar.cc/ | grep -F "今晚看什么？"
curl -fsS https://cinebar.cc/health | grep -F '"cinebar-website"'
curl -fsS https://share.cinebar.cc/updates/latest.json | grep -F '"build":16'
```

Expected:

- HTTP redirects to HTTPS;
- the homepage and website health response come from the Site;
- the Build 16 update manifest remains on the Share Worker.

- [ ] **Step 8: Commit**

```bash
git add CineBarShare/wrangler.jsonc \
  CineBarShare/tests/share-worker.test.mjs \
  CineBarWebsite/.openai/hosting.json
git commit -m "ops: move CineBar apex to product website"
```
