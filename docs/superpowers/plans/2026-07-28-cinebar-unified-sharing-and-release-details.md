# CineBar Unified Sharing and Release Details Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a local CineBar 0.8.2 Build 16 feature-preview package whose single system-share button behaves like Safari for web links, whose share pages show cast and a GitHub Releases entry, and whose Upcoming list shows release dates.

**Architecture:** Replace the current text-plus-URL share payload with one remote URL item and present it directly through `NSSharingServicePicker`. Extend the existing share Worker with an optional credits request and a fixed HTTPS Releases-page configuration, while keeping movie/TV short paths stable. Add a pure, testable release-date presentation type and pass its value into `MovieRow` only from the Upcoming shelf.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSSharingServicePicker`, Foundation date formatting, Cloudflare Workers, Node.js built-in test runner, Wrangler 4, universal arm64/x86_64 packaging.

## Global Constraints

- The share picker receives exactly one remote `NSURL`; it must not receive a separate `NSString`.
- The movie and television detail views expose one direct Share button, with no X, Weibo, WeChat, or Instagram-specific actions.
- X is a Chrome web app on the test Mac and is not expected to appear as a native macOS sharing service.
- The system share sheet's Copy action is the platform-neutral fallback.
- Share preview titles use `《影片名称》— CineBar`.
- Existing permanent routes remain `/m/<TMDB ID>` and `/t/<TMDB ID>`.
- Share pages show at most the first six TMDB cast members in source order.
- A cast member shows `演员姓名` and, when present, `饰 角色名`.
- Cast failure or empty cast must not prevent the detail page from rendering.
- The download entry is exactly `https://github.com/leeugm-create/CineBar/releases` and is labeled as a versions/download page, not a guaranteed stable release.
- Upcoming rows use the existing list `release_date`; they do not issue per-row network requests.
- Upcoming rows always show either a localized valid date or `上映日期待定`.
- Other movie shelves do not show the upcoming-date label.
- Do not purchase or configure `cinebar.cc` in this plan.
- Do not claim that this build fixes mainland China DNS/TLS reachability.
- Do not publish a GitHub Release or upload the preview package.
- The deliverable is a local-only `CineBar-0.8.2-share-preview-universal.zip`, `CFBundleShortVersionString` `0.8.2`, `CFBundleVersion` `16`.
- The paused custom-domain plan must be revised to Build 17 before it resumes; Build 16 belongs to this feature preview.

## File Structure

- `CineBar/Sources/CineBar/main.swift`: single-item share payload, direct Share button, and upcoming-date presentation.
- `CineBar/Tests/RegressionBehaviorTests.swift`: Swift regression coverage for one-item sharing and release-date states.
- `CineBar/Assets/Localization/*.lproj/Localizable.strings`: remove obsolete platform actions and add the undated label in five localizations.
- `CineBarShare/worker.js`: optional credits load, cast rendering, branded preview title, and safe download entry.
- `CineBarShare/tests/share-worker.test.mjs`: Worker coverage for cast limits, escaping, cast failure, titles, and the Releases URL.
- `CineBarShare/wrangler.jsonc`: configure the exact GitHub Releases HTTPS URL.
- `CineBar/Info.plist`: Build 16 metadata only; service URLs remain unchanged.
- `CineBar/Tools/build_test_package.sh`: feature-preview archive name.
- `CineBar/README.md`: unified share behavior and current network limitation.
- `CineBar/请先阅读-测试版安装说明.html`: feature-preview installation and sharing notes.
- `CineBar/请先阅读-测试版安装说明.txt`: plain-text equivalent.
- `dist/CineBar-0.8.2-share-preview-universal.zip`: local verification artifact.

---

### Task 1: Replace Platform Menus with One Safari-Style Share Item

**Files:**
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Assets/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/zh-Hant.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/en.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ja.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ko.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `BrandedShareLink.url(baseURL:mediaType:mediaID:) -> URL?`.
- Produces: `SharePayload(mediaType:title:url:)`, `SharePayload.systemItems: [Any]`, and `MediaShareButton`.

- [ ] **Step 1: Replace the old share-text assertions with a failing one-item regression**

In `RegressionBehaviorTests.swift`, replace construction and assertions for the movie and television text payloads with:

```swift
let moviePayload = SharePayload(
    mediaType: .movie,
    title: "沙丘2",
    url: movieShareURL!
)
let movieShareItems = moviePayload.systemItems
precondition(movieShareItems.count == 1)
precondition(movieShareItems[0] is NSURL)
precondition(!(movieShareItems[0] is NSString))
precondition(
    (movieShareItems[0] as? NSURL)?.absoluteString ==
        "https://share.example/m/603"
)

let televisionPayload = SharePayload(
    mediaType: .tv,
    title: "幕府将军",
    url: televisionShareURL!
)
let televisionShareItems = televisionPayload.systemItems
precondition(televisionShareItems.count == 1)
precondition(
    (televisionShareItems[0] as? NSURL)?.absoluteString ==
        "https://share.example/t/1399"
)
```

- [ ] **Step 2: Run the Swift regression executable and verify it fails**

Run:

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-share-regression
/tmp/cinebar-share-regression
```

Expected: compilation fails because `SharePayload` does not have the new initializer or `systemItems`.

- [ ] **Step 3: Reduce `SharePayload` to the single web item**

Replace the existing text-building properties with:

```swift
struct SharePayload {
    let mediaType: CommunityMediaType
    let title: String
    let url: URL

    var systemItems: [Any] {
        [url as NSURL]
    }
}
```

Keep `mediaType` and `title` because they describe the share item and are useful for accessibility and diagnostics. Remove the old `year`, `tmdbScore`, `cineBarScore`, `text`, and `scoreText` code.

- [ ] **Step 4: Make the presenter consume only `systemItems`**

Change the picker initialization to:

```swift
let picker = NSSharingServicePicker(items: payload.systemItems)
```

Do not add a second item, custom X service, or platform-specific delegate.

- [ ] **Step 5: Replace `MediaShareMenu` with a direct button**

Replace the menu, X URL, Weibo URL, and pasteboard actions with:

```swift
struct MediaShareButton: View {
    let payload: SharePayload?

    var body: some View {
        Button {
            if let payload {
                SystemSharePresenter.present(payload)
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.plain)
        .disabled(payload == nil)
        .help(payload == nil ? "分享服务暂不可用" : "分享")
        .accessibilityLabel("分享")
    }
}
```

Replace both detail call sites with:

```swift
MediaShareButton(payload: sharePayload)
```

Update the two payload constructors to pass only `mediaType`, `title`, and `url`.

- [ ] **Step 6: Remove obsolete platform menu localization keys**

Remove these keys from all five `Localizable.strings` files:

```text
复制分享文案
系统分享（微信、Instagram 等）
分享到 X
分享到微博
部署 CineBar 分享服务后可使用品牌分享页面
```

Ensure the shared `"分享"` key exists in every localization:

```text
zh-Hans: "分享"
zh-Hant: "分享"
en: "Share"
ja: "共有"
ko: "공유"
```

Add `"分享服务暂不可用"` in every localization:

```text
zh-Hans: "分享服务暂不可用"
zh-Hant: "分享服務暫時無法使用"
en: "Sharing is temporarily unavailable"
ja: "共有サービスは一時的に利用できません"
ko: "공유 서비스를 일시적으로 사용할 수 없습니다"
```

- [ ] **Step 7: Run the regression, compiler, and localization checks**

Run:

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-share-regression
/tmp/cinebar-share-regression

xcrun swiftc -parse-as-library -typecheck \
  CineBar/Sources/CineBar/main.swift

for strings in CineBar/Assets/Localization/*.lproj/Localizable.strings; do
  plutil -lint "$strings"
done

! rg -n '分享到 X|分享到微博|系统分享（微信、Instagram 等）' \
  CineBar/Sources/CineBar CineBar/Assets/Localization
```

Expected: all commands pass and the final search finds no matches.

- [ ] **Step 8: Commit**

```bash
git add CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  CineBar/Assets/Localization
git commit -m "fix: share CineBar links as one web item"
```

---

### Task 2: Add Cast and the Releases Entry to Share Pages

**Files:**
- Modify: `CineBarShare/tests/share-worker.test.mjs`
- Modify: `CineBarShare/worker.js`
- Modify: `CineBarShare/wrangler.jsonc`

**Interfaces:**
- Consumes: existing `mediaPath`, permanent short routes, `TMDB_BEARER_TOKEN`, and injectable `MEDIA_FETCHER`.
- Produces: `loadMetadata(route, env)` metadata with `cast: Array<{name: string, character: string}>`.

- [ ] **Step 1: Expand Worker fixtures and add failing cast/title assertions**

Add credits fixtures:

```javascript
const movieCast = [
  { name: "Keanu Reeves", character: "Neo" },
  { name: "Carrie-Anne Moss", character: "Trinity" },
  { name: "Laurence Fishburne", character: "Morpheus" },
  { name: "Hugo Weaving", character: "Agent Smith" },
  { name: "Gloria Foster", character: "Oracle" },
  { name: "Joe Pantoliano", character: "Cypher" },
  { name: "Should Not Render", character: "Seventh" },
];
```

Update `metadataFetcher` so `/credits` returns `{ cast: movieCast }` for movies and a two-member TV cast for television. Then extend the movie page test:

```javascript
assert.match(html, /<title>《The Matrix》— CineBar<\/title>/);
assert.match(html, /主要演员/);
assert.match(html, /Keanu Reeves/);
assert.match(html, /饰 Neo/);
assert.doesNotMatch(html, /Should Not Render/);
```

Add a malicious cast member to a dedicated fixture and assert:

```javascript
assert.match(html, /&lt;script&gt;/);
assert.doesNotMatch(html, /<script>/);
```

- [ ] **Step 2: Add a failing optional-credits test**

Add:

```javascript
test("keeps the share page when credits fail", async () => {
  const response = await fetchPage("/m/603", {
    MEDIA_FETCHER: async (requestURL) => {
      if (String(requestURL).includes("/credits")) {
        return new Response("upstream error", { status: 503 });
      }
      return metadataFetcher(requestURL);
    },
  });
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.match(html, /The Matrix/);
  assert.doesNotMatch(html, /主要演员/);
});
```

- [ ] **Step 3: Add a failing exact-download test**

Change the valid-download fixture to:

```javascript
CINEBAR_DOWNLOAD_URL:
  "https://github.com/leeugm-create/CineBar/releases",
```

Assert both the exact URL and the label:

```javascript
assert.match(htmlWithDownload, /查看 CineBar 版本与下载/);
assert.match(
  htmlWithDownload,
  /https:\/\/github\.com\/leeugm-create\/CineBar\/releases/,
);
```

- [ ] **Step 4: Run Worker tests and verify failure**

Run:

```bash
node --test CineBarShare/tests/share-worker.test.mjs
```

Expected: the new cast, title, and download-label assertions fail.

- [ ] **Step 5: Split required details from optional credits**

Add one authenticated JSON helper and make `loadMetadata` request details first and credits separately:

```javascript
const loadTMDBJSON = async (endpoint, env) => {
  const fetcher = env.MEDIA_FETCHER ?? fetch;
  const response = await fetcher(endpoint.href, {
    headers: {
      accept: "application/json",
      authorization: `Bearer ${env.TMDB_BEARER_TOKEN}`,
    },
  });
  if (!response.ok) {
    throw new Error(`TMDB request failed with ${response.status}`);
  }
  return response.json();
};
```

Use:

```javascript
const basePath = `${route.mediaType}/${route.mediaID}`;
const detailsURL = new URL(`https://api.themoviedb.org/3/${basePath}`);
detailsURL.searchParams.set("language", "zh-CN");
const payload = await loadTMDBJSON(detailsURL, env);

const creditsURL = new URL(
  `https://api.themoviedb.org/3/${basePath}/credits`,
);
creditsURL.searchParams.set("language", "zh-CN");
let credits = { cast: [] };
try {
  credits = await loadTMDBJSON(creditsURL, env);
} catch {
  credits = { cast: [] };
}
```

Normalize and limit:

```javascript
cast: Array.isArray(credits.cast)
  ? credits.cast.slice(0, 6).map((member) => ({
      name: normalize(member.name).slice(0, 80),
      character: normalize(member.character).slice(0, 100),
    })).filter((member) => member.name)
  : [],
```

- [ ] **Step 6: Render the title, actor section, and social description**

Use this page title:

```javascript
const brandedTitle = `《${title}》— CineBar`;
```

Use `brandedTitle` in `<title>`, `og:title`, and `twitter:title`.

Create the actor section only when cast is non-empty:

```javascript
const cast = metadata?.cast ?? [];
const castBlock = cast.length
  ? `<section class="cast"><h2>主要演员</h2><div class="cast-list">${
      cast.map((member) =>
        `<div class="cast-member"><strong>${escapeHTML(member.name)}</strong>${
          member.character
            ? `<span>饰 ${escapeHTML(member.character)}</span>`
            : ""
        }</div>`
      ).join("")
    }</div></section>`
  : "";
```

Create a metadata description capped at 300 characters:

```javascript
const castSummary = cast.map((member) => member.name).join("、");
const socialDescription = normalize(
  `${castSummary ? `主演：${castSummary}。` : ""}${summary}`,
).slice(0, 300);
```

Use `socialDescription` for description/Open Graph/Twitter description, while the body retains the full existing summary. Insert `castBlock` below the summary.

Add scoped CSS for `.cast`, `.cast-list`, and `.cast-member`; preserve the responsive one-column layout.

- [ ] **Step 7: Change the download label and configure the Releases URL**

Change the anchor text to:

```html
查看 CineBar 版本与下载
```

Set `CineBarShare/wrangler.jsonc`:

```jsonc
"CINEBAR_DOWNLOAD_URL":
  "https://github.com/leeugm-create/CineBar/releases"
```

- [ ] **Step 8: Run Worker tests**

Run:

```bash
node --test CineBarShare/tests/share-worker.test.mjs
npx wrangler deploy --dry-run --config CineBarShare/wrangler.jsonc
```

Expected: all Worker tests pass and Wrangler validates the bundle.

- [ ] **Step 9: Commit**

```bash
git add CineBarShare/worker.js \
  CineBarShare/tests/share-worker.test.mjs \
  CineBarShare/wrangler.jsonc
git commit -m "feat: enrich CineBar share pages"
```

---

### Task 3: Show Localized Dates on Every Upcoming Movie Row

**Files:**
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Assets/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/zh-Hant.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/en.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ja.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ko.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `Movie.releaseDate`, `MovieStore.appLanguage`, and `MovieBrowseSection.upcoming`.
- Produces: `UpcomingReleasePresentation.make(rawValue:language:)`, `MovieRowPresentation.upcomingRelease(section:rawValue:language:)`, and `MovieRow.upcomingRelease`.

- [ ] **Step 1: Add failing release-date state tests**

Add:

```swift
precondition(
    UpcomingReleasePresentation.make(
        rawValue: "2026-07-31",
        language: .zhCN
    ) == .dated("2026年7月31日")
)
precondition(
    UpcomingReleasePresentation.make(
        rawValue: "2026-07-31",
        language: .zhTW
    ) == .dated("2026年7月31日")
)
precondition(
    UpcomingReleasePresentation.make(
        rawValue: "2026-07-31",
        language: .enUS
    ) == .dated("Jul 31, 2026")
)
precondition(
    UpcomingReleasePresentation.make(
        rawValue: nil,
        language: .zhCN
    ) == .undated
)
precondition(
    UpcomingReleasePresentation.make(
        rawValue: "2026",
        language: .zhCN
    ) == .undated
)
precondition(
    UpcomingReleasePresentation.make(
        rawValue: "not-a-date",
        language: .zhCN
    ) == .undated
)
precondition(
    MovieRowPresentation.upcomingRelease(
        section: .upcoming,
        rawValue: "2026-07-31",
        language: .zhCN
    ) == .dated("2026年7月31日")
)
precondition(
    MovieRowPresentation.upcomingRelease(
        section: .trending,
        rawValue: "2026-07-31",
        language: .zhCN
    ) == nil
)
```

- [ ] **Step 2: Run the regression and verify failure**

Run:

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-upcoming-regression
/tmp/cinebar-upcoming-regression
```

Expected: compilation fails because `UpcomingReleasePresentation` is undefined.

- [ ] **Step 3: Implement the pure presentation type**

Add near `MovieRow`:

```swift
enum UpcomingReleasePresentation: Equatable {
    case dated(String)
    case undated

    static func make(
        rawValue: String?,
        language: AppLanguage
    ) -> UpcomingReleasePresentation {
        guard let rawValue, rawValue.count == 10 else {
            return .undated
        }
        let input = DateFormatter()
        input.calendar = Calendar(identifier: .gregorian)
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        input.isLenient = false
        guard let date = input.date(from: rawValue) else {
            return .undated
        }

        let output = DateFormatter()
        output.calendar = Calendar(identifier: .gregorian)
        switch language {
        case .zhCN, .zhHK, .zhTW:
            output.locale = Locale(identifier: language.localeIdentifier)
            output.dateFormat = "yyyy年M月d日"
        case .enUS:
            output.locale = Locale(identifier: "en_US")
            output.dateFormat = "MMM d, yyyy"
        case .jaJP:
            output.locale = Locale(identifier: "ja_JP")
            output.dateFormat = "yyyy年M月d日"
        case .koKR:
            output.locale = Locale(identifier: "ko_KR")
            output.dateFormat = "yyyy년 M월 d일"
        }
        return .dated(output.string(from: date))
    }
}
```

Add the shelf boundary:

```swift
enum MovieRowPresentation {
    static func upcomingRelease(
        section: MovieBrowseSection,
        rawValue: String?,
        language: AppLanguage
    ) -> UpcomingReleasePresentation? {
        guard section == .upcoming else { return nil }
        return UpcomingReleasePresentation.make(
            rawValue: rawValue,
            language: language
        )
    }
}
```

- [ ] **Step 4: Add the optional presentation to `MovieRow`**

Change the declaration:

```swift
struct MovieRow: View {
    let movie: Movie
    var upcomingRelease: UpcomingReleasePresentation? = nil
```

Above the title, render only when the optional is present:

```swift
if let upcomingRelease {
    switch upcomingRelease {
    case .dated(let date):
        Label(date, systemImage: "calendar")
            .font(.caption2.bold())
            .foregroundStyle(.indigo)
    case .undated:
        Label("上映日期待定", systemImage: "calendar.badge.questionmark")
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 5: Pass the state only from the Upcoming list**

At the movie-list call site use:

```swift
MovieRow(
    movie: movie,
    upcomingRelease: MovieRowPresentation.upcomingRelease(
        section: store.movieBrowseSection,
        rawValue: movie.releaseDate,
        language: store.appLanguage
    )
)
```

Leave watchlist and recommendation call sites unchanged so their default remains `nil`.

- [ ] **Step 6: Add the undated localization**

Add:

```text
zh-Hans: "上映日期待定" = "上映日期待定";
zh-Hant: "上映日期待定" = "上映日期待定";
en: "上映日期待定" = "Release date to be announced";
ja: "上映日期待定" = "公開日未定";
ko: "上映日期待定" = "개봉일 미정";
```

- [ ] **Step 7: Run regressions and localization checks**

Run:

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-upcoming-regression
/tmp/cinebar-upcoming-regression

xcrun swiftc -parse-as-library -typecheck \
  CineBar/Sources/CineBar/main.swift

for strings in CineBar/Assets/Localization/*.lproj/Localizable.strings; do
  plutil -lint "$strings"
done
```

Expected: all checks pass.

- [ ] **Step 8: Commit**

```bash
git add CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  CineBar/Assets/Localization
git commit -m "feat: show upcoming movie release dates"
```

---

### Task 4: Deploy the Share Preview, Package Build 16, and Verify WeChat

**Files:**
- Modify: `CineBar/Info.plist`
- Modify: `CineBar/Tools/build_test_package.sh`
- Modify: `CineBar/README.md`
- Modify: `CineBar/请先阅读-测试版安装说明.html`
- Modify: `CineBar/请先阅读-测试版安装说明.txt`
- Create: `dist/CineBar-0.8.2-share-preview-universal.zip`

**Interfaces:**
- Consumes: Task 1's one-URL system share item, Task 2's Worker page, and Task 3's row presentation.
- Produces: live `cinebar-share-test.leeugm.workers.dev` preview and a local-only Build 16 universal archive.

- [ ] **Step 1: Update Build 16 and preview package naming**

Set `CFBundleVersion` to:

```xml
<string>16</string>
```

Keep `CFBundleShortVersionString` at `0.8.2`.

Set in `build_test_package.sh`:

```bash
package_name="CineBar-0.8.2-share-preview"
```

- [ ] **Step 2: Update documentation with exact limitations**

Document all of the following in the README and both installation guides:

- one Share button opens the macOS system share sheet directly;
- CineBar submits one webpage link so compatible extensions such as WeChat can appear;
- the Copy item is the fallback for apps without a native sharing extension;
- X installed as a Chrome web app will not appear as a native service;
- share pages show up to six cast members and link to the GitHub Releases page;
- Upcoming rows show a date or “上映日期待定”;
- this is a local feature preview, not a mainland network fix;
- `workers.dev` may still fail on some mainland networks;
- no domain, Cloudflare, API-key, or database setup is required from the preview user.

Do not say that X or every third-party app is guaranteed to appear.

- [ ] **Step 3: Run the complete local test suite**

Run:

```bash
node --test CineBarDataProxy/tests/data-proxy.test.mjs
node --test CineBarCommunity/tests/community-rating.test.mjs
node --test CineBarShare/tests/share-worker.test.mjs

xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-preview-regression
/tmp/cinebar-preview-regression

xcrun swiftc -parse-as-library -typecheck \
  CineBar/Sources/CineBar/main.swift

plutil -lint CineBar/Info.plist
for strings in CineBar/Assets/Localization/*.lproj/Localizable.strings; do
  plutil -lint "$strings"
done
git diff --check
```

Expected: all tests and checks pass.

- [ ] **Step 4: Deploy only the existing test share Worker**

Verify the authenticated account, then deploy to the existing test service name:

```bash
npx wrangler whoami
npx wrangler deploy \
  --config CineBarShare/wrangler.jsonc \
  --name cinebar-share-test
```

Do not deploy Data or Community Workers and do not create a new Worker name.

- [ ] **Step 5: Smoke-test the live share service**

Run:

```bash
curl --fail --silent --show-error \
  https://cinebar-share-test.leeugm.workers.dev/m/603 \
  | rg '《.+》— CineBar|主要演员|查看 CineBar 版本与下载'

curl --fail --silent --show-error \
  https://cinebar-share-test.leeugm.workers.dev/t/1399 \
  | rg '《.+》— CineBar|主要演员|查看 CineBar 版本与下载'
```

Use the existing system proxy if required on the development Mac. This smoke test proves Worker behavior only; it does not prove mainland reachability.

- [ ] **Step 6: Build the local preview archive**

Run:

```bash
CineBar/Tools/build_test_package.sh
test -f dist/CineBar-0.8.2-share-preview-universal.zip
```

- [ ] **Step 7: Verify archive architecture, signature, metadata, and contents**

Run:

```bash
preview_dir=$(mktemp -d \
  "${TMPDIR:-/tmp}/cinebar-share-preview.XXXXXX")
ditto -x -k dist/CineBar-0.8.2-share-preview-universal.zip \
  "$preview_dir"
preview_app=$(find "$preview_dir" -type d -name CineBar.app -print -quit)
test -n "$preview_app"
lipo -archs "$preview_app/Contents/MacOS/CineBar" \
  | rg 'arm64'
lipo -archs "$preview_app/Contents/MacOS/CineBar" \
  | rg 'x86_64'
codesign --verify --deep --strict "$preview_app"
test "$(plutil -extract CFBundleVersion raw \
  "$preview_app/Contents/Info.plist")" = "16"
find "$preview_dir" -name '请先阅读-测试版安装说明.html' \
  -print -quit | grep -q .
find "$preview_dir" -name '请先阅读-测试版安装说明.txt' \
  -print -quit | grep -q .
shasum -a 256 dist/CineBar-0.8.2-share-preview-universal.zip
```

- [ ] **Step 8: Perform the manual WeChat acceptance test**

On the user's Mac:

1. launch the extracted Build 16 app;
2. open a real movie detail page;
3. click the Share icon once;
4. verify the system sheet opens directly;
5. verify exactly one branded webpage preview appears;
6. verify “发送到微信” is listed;
7. choose WeChat and confirm its composer opens;
8. cancel without sending;
9. reopen sharing, choose Copy, and paste into a temporary text field;
10. verify the copied value is the permanent `/m/<ID>` URL;
11. repeat the preview check for one television page;
12. verify every visible Upcoming row shows either a date or “上映日期待定”.

If WeChat still does not appear, stop the release. Inspect the runtime picker items and confirm the sole item is `NSURL`; do not restore platform-specific buttons.

- [ ] **Step 9: Copy the local artifact without uploading**

```bash
mkdir -p /Users/bruce/Documents/Codex/2026-07-25/you/work/CineBar/build082
cp dist/CineBar-0.8.2-share-preview-universal.zip \
  /Users/bruce/Documents/Codex/2026-07-25/you/work/CineBar/build082/
```

- [ ] **Step 10: Commit locally**

```bash
git add CineBar/Info.plist \
  CineBar/Tools/build_test_package.sh \
  CineBar/README.md \
  CineBar/请先阅读-测试版安装说明.html \
  CineBar/请先阅读-测试版安装说明.txt \
  dist/CineBar-0.8.2-share-preview-universal.zip
git commit -m "build: package CineBar sharing preview"
```

Do not push, upload the archive, or create a GitHub Release.
