# CineBar 手机首页内嵌播放器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 CineBar 手机浏览器首页以 Logo + 搜索为入口，点击搜索结果后在当前页按需展开安全的内嵌播放器，不跳转到分享页。

**Architecture:** 保留桌面端 `SiteSearch` 的链接行为；在同一搜索组件内增加移动端结果激活状态和 `InlinePlayer` 子组件。播放器只在用户点击播放且结果包含经过校验的 HTTPS 播放源后创建媒体元素；当前 TMDB 搜索接口没有播放源时显示明确的无源状态。移动布局只通过 `.site-home` 的手机断点样式生效，桌面首页、App 和分享页不变。

**Tech Stack:** Next/Vinext App Router、React 19、TypeScript、原生 `<video>`/HLS-compatible URL、现有 CSS、Node `node:test` 网站测试。

## Global Constraints

- 只改 `CineBarWebsite` 官网首页在手机浏览器中的表现；桌面端、App、分享页、下载入口和支持页不改变。
- 采用 `搜索结果 → 点击影片 → 首页内展开播放器 → 用户点击播放`。
- 首次页面渲染和仅搜索时不得建立视频网络请求。
- 只接受 `https:` 且明确可网页播放/嵌入的合法播放源；不抓取或代理盗版站、迅雷/磁力链接、防盗链或 DRM 资源。
- 没有播放源时必须显示“暂无可在线播放源”，不能显示空播放器或伪造“可观看”。
- 任何时间最多一个活跃播放器；关闭或切换时暂停并释放旧播放器。
- 手机浏览器可能阻止带声音自动播放，播放器必须由用户点击开始。
- 继续支持现有简体中文、繁体中文、英语、日语和韩语文案。

---

### Task 1: Add a safe inline player component and mobile result activation

**Files:**
- Create: `CineBarWebsite/app/inline-player.tsx`
- Modify: `CineBarWebsite/app/site-search.tsx`
- Test: `CineBarWebsite/tests/mobile-inline-player.test.mjs`

**Interfaces:**
- `InlinePlayer` consumes `SearchHit`, localized labels, and `onClose`.
- `SearchHit` gains optional `watch?: WatchSource[]` while retaining current `type/id/title/year/poster/rating` fields.
- `WatchSource` is `{ kind: "html5" | "hls"; url: string; label: string; region?: string }` for this first safe implementation.
- `SiteSearch` keeps desktop anchors and opens `InlinePlayer` only when `matchMedia("(max-width: 560px)")` matches.

- [ ] **Step 1: Write source-level regression tests**

  Add tests that read the two components and assert:

  ```js
  assert.match(search, /matchMedia\(["']\\(max-width: 560px\\)/);
  assert.match(search, /InlinePlayer/);
  assert.match(player, /preload=["']none["']/);
  assert.match(player, /https:/);
  assert.match(player, /暂无可在线播放源|playerNoSource/);
  assert.doesNotMatch(search, /window\.location/);
  ```

- [ ] **Step 2: Run the focused test and verify it fails**

  Run: `node --test tests/mobile-inline-player.test.mjs` from `CineBarWebsite`.

  Expected: FAIL because the new component and mobile activation do not exist yet.

- [ ] **Step 3: Implement `InlinePlayer`**

  Render a compact card with poster and play button before activation. Validate the selected source with `new URL`; reject non-HTTPS URLs. On play, render one native `<video controls playsInline preload="none">` with the validated source and include an error state plus retry. If `watch` is absent or empty, render the poster and localized no-source state without creating a media element. Always expose a 44px close button.

- [ ] **Step 4: Connect selection and cleanup in `SiteSearch`**

  Add `selected` state. On a mobile result click, call `preventDefault()`, set the selected result, and keep the URL unchanged. Render the player above the result list. Clear selection when the query changes, the search closes, or a different result is selected. Keep desktop result links targeting the existing `share.cinebar.cc` URLs.

- [ ] **Step 5: Run the focused test**

  Run: `node --test tests/mobile-inline-player.test.mjs`.

  Expected: PASS.

- [ ] **Step 6: Commit the focused component change**

  ```bash
  git add CineBarWebsite/app/inline-player.tsx CineBarWebsite/app/site-search.tsx CineBarWebsite/tests/mobile-inline-player.test.mjs
  git commit -m "feat: add mobile inline player shell"
  ```

### Task 2: Make the homepage mobile-first without changing desktop

**Files:**
- Modify: `CineBarWebsite/app/home.tsx`
- Modify: `CineBarWebsite/app/globals.css`
- Test: `CineBarWebsite/tests/mobile-inline-player.test.mjs`

**Interfaces:**
- Add `className="site-home"` to the homepage `<main>` so the mobile-only rules cannot affect support/admin pages.
- Keep the existing desktop `hero`, showcase, sections, and footer markup.

- [ ] **Step 1: Extend focused tests with mobile layout assertions**

  Assert that `home.tsx` contains `site-home`, and CSS contains mobile rules for hiding desktop nav controls, full-width open search, full-width results, and a 16:9 player card.

- [ ] **Step 2: Run the focused test and verify the new assertions fail**

  Run: `node --test tests/mobile-inline-player.test.mjs`.

- [ ] **Step 3: Add scoped mobile CSS**

  Inside `@media (max-width: 560px)` and under `.site-home`:

  - show only Logo/name and search toggle in the sticky header;
  - when open, make the search input and result panel full width with 44px controls;
  - use compact result rows with poster, title, metadata, rating and play status;
  - style the inline player as a stable 16:9 surface with poster, play, close, loading, error and no-source states;
  - reduce the hero to a short search-first introduction, hide the large GIF and desktop action row from the mobile first screen;
  - keep later content reachable by scrolling and prevent horizontal overflow;
  - preserve dark mode and reduced-motion behavior.

- [ ] **Step 4: Run the focused test**

  Run: `node --test tests/mobile-inline-player.test.mjs`.

  Expected: PASS.

- [ ] **Step 5: Commit the mobile layout change**

  ```bash
  git add CineBarWebsite/app/home.tsx CineBarWebsite/app/globals.css CineBarWebsite/tests/mobile-inline-player.test.mjs
  git commit -m "feat: focus CineBar homepage search on mobile"
  ```

### Task 3: Add localized playback labels and preserve the current source contract

**Files:**
- Modify: `CineBarWebsite/app/i18n.ts`
- Modify: `CineBarWebsite/tests/content.test.mjs`

**Interfaces:**
- Add `playerPlay`, `playerClose`, `playerRetry`, `playerNoSource`, `playerLoading`, `playerError`, and `playerSource` to `Messages` and all five locales.

- [ ] **Step 1: Add localization assertions**

  Extend `content.test.mjs` to require all seven keys in the interface and to ensure the current public brand/download copy remains intact.

- [ ] **Step 2: Run the content test and verify it fails**

  Run: `node --test tests/content.test.mjs` from `CineBarWebsite`.

- [ ] **Step 3: Add translations**

  Add concise, equivalent labels for Simplified Chinese, Traditional Chinese, English, Japanese, and Korean. Do not change existing desktop copy.

- [ ] **Step 4: Run the content test**

  Run: `node --test tests/content.test.mjs`.

  Expected: PASS.

- [ ] **Step 5: Commit localization**

  ```bash
  git add CineBarWebsite/app/i18n.ts CineBarWebsite/tests/content.test.mjs
  git commit -m "feat: localize mobile player states"
  ```

### Task 4: Build, verify, and deploy the mobile homepage

**Files:**
- Verify: `CineBarWebsite/app/home.tsx`
- Verify: `CineBarWebsite/app/site-search.tsx`
- Verify: `CineBarWebsite/app/inline-player.tsx`
- Verify: `CineBarWebsite/app/globals.css`
- Verify: `CineBarWebsite/worker/index.ts`

- [ ] **Step 1: Run the full website test suite**

  Run: `npm test` from `CineBarWebsite`.

  Expected: all tests pass, including mobile inline-player coverage.

- [ ] **Step 2: Run lint**

  Run: `npm run lint` from `CineBarWebsite`.

  Expected: zero errors; existing image-element warnings may remain unchanged.

- [ ] **Step 3: Run a production dry run**

  Run: `CI=1 npm run deploy:dry-run` from `CineBarWebsite`.

  Expected: build and Wrangler dry run exit 0.

- [ ] **Step 4: Verify the generated homepage contract**

  Confirm the built output contains `site-home`, `InlinePlayer`, the five locale strings, no third-party stream endpoint, and the existing Build 62 download/appcast references.

- [ ] **Step 5: Deploy once to the existing Cloudflare Worker**

  Run: `CI=1 npm run deploy:public` from `CineBarWebsite`.

  Expected: `cinebar-website` deploys to the existing `cinebar.cc` custom domain without DNS changes.

- [ ] **Step 6: Verify the public deployment**

  Check:

  ```bash
  curl -fsSI https://cinebar.cc/
  curl -fsS -A 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)' https://cinebar.cc/ | rg 'site-home|找到下一部好片|搜索'
  curl -fsSI https://cinebar.cc/appcast.xml
  ```

  Expected: HTTPS 200 responses; mobile HTML includes the mobile homepage marker and current brand copy; appcast remains available.

- [ ] **Step 7: Record deployment evidence**

  Save the Wrangler version ID, public URL, test results, and the explicit “no legal playback source configured yet” limitation in `.superpowers/sdd/2026-08-11-cinebar-mobile-inline-player/deploy-report.md`, then commit the report.

