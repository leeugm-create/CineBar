# CineBar 0.8.1-test.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and package CineBar 0.8.1-test.2 with passwordless anonymous identity, separate official and CineBar age-rating cards, adjustable glass-background opacity, short movie/TV share links, informative system-share text, and an optional download entry on branded share pages.

**Architecture:** Keep the macOS client as one existing Swift source file and add small pure helpers for behavior that must be regression-tested. Store the anonymous UUID and glass opacity in `UserDefaults`; render opacity only in the SwiftUI background layer. Make the independent Cloudflare Share Worker resolve `/m/:id` and `/t/:id` from TMDB using a Worker secret, while the client always sends readable share text alongside the short URL.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Foundation, UserDefaults, Cloudflare Workers, TMDB API, Node.js built-in test runner, Wrangler, universal arm64/x86_64 packaging.

## Global Constraints

- Target version is `0.8.1-test.2` with `CFBundleVersion` `14`.
- The package remains a test build and must not be uploaded to GitHub.
- Anonymous rating continues to require no user account.
- Each device can score a given movie or TV show once; scores remain immutable.
- Glass-background opacity is 50%–100%, defaults to 85%, updates immediately, and never fades foreground content.
- Movie short links use `/m/<TMDB ID>` and TV short links use `/t/<TMDB ID>`.
- Short links do not expire.
- System-share text includes title, year, TMDB score, optional CineBar score, a short prompt, and the short URL.
- A missing download URL hides the download control completely.
- The delivered ZIP contains `CineBar.app` plus detailed HTML and text installation instructions.
- Do not add third-party dependencies.

---

### Task 1: Replace Keychain Identity with UserDefaults Identity

**Files:**
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:**
- Consumes: `UserDefaults`.
- Produces: `CineBarDeviceIdentity.value(defaults: UserDefaults = .standard) -> String`.

- [ ] **Step 1: Add a failing passwordless-identity regression test**

Add an isolated defaults suite and verify the generated UUID is stable:

```swift
let identitySuite = "CineBarIdentityTests.\(UUID().uuidString)"
let identityDefaults = UserDefaults(suiteName: identitySuite)!
identityDefaults.removePersistentDomain(forName: identitySuite)
let firstIdentity = CineBarDeviceIdentity.value(defaults: identityDefaults)
let secondIdentity = CineBarDeviceIdentity.value(defaults: identityDefaults)
precondition(firstIdentity == secondIdentity)
precondition(UUID(uuidString: firstIdentity) != nil)
precondition(
    identityDefaults.string(
        forKey: CineBarDeviceIdentity.defaultsKey
    ) == firstIdentity
)
identityDefaults.removePersistentDomain(forName: identitySuite)
```

- [ ] **Step 2: Run the Swift regression test and verify RED**

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-test2-regression
/tmp/cinebar-test2-regression
```

Expected: compilation fails because `defaultsKey` and the injectable `defaults` argument do not exist.

- [ ] **Step 3: Implement UserDefaults-backed identity**

Replace the Security-framework implementation with:

```swift
enum CineBarDeviceIdentity {
    static let defaultsKey = "communityAnonymousInstallID"

    static func value(defaults: UserDefaults = .standard) -> String {
        if let saved = defaults.string(forKey: defaultsKey),
           UUID(uuidString: saved) != nil {
            return saved
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: defaultsKey)
        return created
    }
}
```

Remove the now-unused `import Security` and all `SecItemCopyMatching`,
`SecItemAdd`, `kSecClass`, `kSecAttrService`, and `kSecAttrAccount` references.
Do not read or delete the legacy Keychain entry.

- [ ] **Step 4: Run the regression test and source scan**

```bash
/tmp/cinebar-test2-regression
! rg -n 'SecItem|kSecClass|kSecAttrService|import Security' \
  CineBar/Sources/CineBar/main.swift
```

Expected: tests pass and the source scan returns no matches.

- [ ] **Step 5: Commit**

```bash
git add CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "fix: store anonymous identity without keychain"
```

---

### Task 2: Split Official and CineBar Age Classifications

**Files:**
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:**
- Consumes: `ContentRatingSummary?`.
- Produces: `ContentRatingPresentation.init(_:)`, with `regionLabel`,
  `officialValue`, and `cineBarValue`; `ContentRatingBadge` renders two cards.

- [ ] **Step 1: Add failing presentation tests**

Add:

```swift
let ratedPresentation = ContentRatingPresentation(
    ContentRatingSummary(
        region: "US",
        original: "PG-13",
        cineBar: "13+"
    )
)
precondition(ratedPresentation.regionLabel == "US")
precondition(ratedPresentation.officialValue == "PG-13")
precondition(ratedPresentation.cineBarValue == "13+")

let unratedPresentation = ContentRatingPresentation(nil)
precondition(unratedPresentation.regionLabel == "地区分级")
precondition(unratedPresentation.officialValue == "未分级")
precondition(unratedPresentation.cineBarValue == "未分级")
```

- [ ] **Step 2: Run the Swift regression test and verify RED**

Run the Task 1 Swift compile-and-run command.

Expected: compilation fails because `ContentRatingPresentation` does not exist.

- [ ] **Step 3: Add the pure presentation model**

Add:

```swift
struct ContentRatingPresentation {
    let regionLabel: String
    let officialValue: String
    let cineBarValue: String

    init(_ rating: ContentRatingSummary?) {
        regionLabel = rating?.region.isEmpty == false
            ? rating!.region
            : "地区分级"
        officialValue = rating?.original.isEmpty == false
            ? rating!.original
            : "未分级"
        cineBarValue = rating?.cineBar.isEmpty == false
            ? rating!.cineBar
            : "未分级"
    }
}
```

- [ ] **Step 4: Replace the combined badge with two matching cards**

Create a focused `CertificationCard` view accepting `label`, `value`,
`accent`, and `symbol`. Render:

```swift
HStack(spacing: 10) {
    CertificationCard(
        label: presentation.regionLabel,
        value: presentation.officialValue,
        accent: .red,
        symbol: "person.badge.shield.checkmark.fill"
    )
    CertificationCard(
        label: "CineBar 分级",
        value: presentation.cineBarValue,
        accent: .orange,
        symbol: "play.rectangle.fill"
    )
}
```

Both cards must use the same minimum width, padding, corner radius, border
width, label font, and value font. The official value is large, bold, and red;
the CineBar value is equally large and bold but orange. Do not move community
quality scores out of the “多重评分” section.

- [ ] **Step 5: Run Swift verification**

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-test2-regression
/tmp/cinebar-test2-regression
xcrun swiftc -parse-as-library -typecheck \
  CineBar/Sources/CineBar/main.swift
```

Expected: all commands pass.

- [ ] **Step 6: Commit**

```bash
git add CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "feat: split official and CineBar classifications"
```

---

### Task 3: Add Background-Only Glass Opacity

**Files:**
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`
- Modify: `CineBar/Assets/Localization/zh-Hant.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/en.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ja.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ko.lproj/Localizable.strings`

**Interfaces:**
- Consumes: persisted `Double` under `glassBackgroundOpacity`.
- Produces: `GlassBackgroundOpacity.normalized(_:) -> Double`,
  `MovieStore.glassBackgroundOpacity`, and
  `MovieStore.setGlassBackgroundOpacity(_:)`.

- [ ] **Step 1: Add failing normalization tests**

Add:

```swift
precondition(GlassBackgroundOpacity.normalized(nil) == 0.85)
precondition(GlassBackgroundOpacity.normalized(0.2) == 0.5)
precondition(GlassBackgroundOpacity.normalized(0.73) == 0.73)
precondition(GlassBackgroundOpacity.normalized(1.4) == 1.0)
```

- [ ] **Step 2: Run the Swift regression test and verify RED**

Run the Task 2 Swift compile-and-run command.

Expected: compilation fails because `GlassBackgroundOpacity` does not exist.

- [ ] **Step 3: Implement the value policy and persistence**

Add:

```swift
enum GlassBackgroundOpacity {
    static let defaultsKey = "glassBackgroundOpacity"
    static let defaultValue = 0.85
    static let range = 0.5...1.0

    static func normalized(_ value: Double?) -> Double {
        min(max(value ?? defaultValue, range.lowerBound), range.upperBound)
    }
}
```

Add `@Published var glassBackgroundOpacity: Double` to `MovieStore`, initialize
it from `UserDefaults`, and add:

```swift
func setGlassBackgroundOpacity(_ value: Double) {
    let normalized = GlassBackgroundOpacity.normalized(value)
    glassBackgroundOpacity = normalized
    defaults.set(
        normalized,
        forKey: GlassBackgroundOpacity.defaultsKey
    )
}
```

- [ ] **Step 4: Add the Appearance setting**

In the existing Appearance settings card, add:

```swift
HStack {
    Text("玻璃背景不透明度")
    Spacer()
    Text("\(Int((store.glassBackgroundOpacity * 100).rounded()))%")
        .monospacedDigit()
        .foregroundStyle(.secondary)
}
Slider(
    value: Binding(
        get: { store.glassBackgroundOpacity },
        set: { store.setGlassBackgroundOpacity($0) }
    ),
    in: GlassBackgroundOpacity.range,
    step: 0.01
)
Button("恢复默认") {
    store.setGlassBackgroundOpacity(
        GlassBackgroundOpacity.defaultValue
    )
}
```

Add translations for “玻璃背景不透明度” and “恢复默认” in Traditional
Chinese, English, Japanese, and Korean.

- [ ] **Step 5: Render opacity in a background-only layer**

In `ContentView`, place the current decorative gradient over:

```swift
Color(nsColor: .windowBackgroundColor)
    .opacity(store.glassBackgroundOpacity)
```

Use a `ZStack` or background overlay so this color and the existing gradient
are behind the root `Group`. Do not set `panel.alphaValue`, `container.alphaValue`,
or opacity on the root content group. This keeps text, posters, buttons,
trailers, and settings fully opaque while the main panel updates immediately
through `@Published`.

- [ ] **Step 6: Run Swift tests, type-check, and localization validation**

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-test2-regression
/tmp/cinebar-test2-regression
xcrun swiftc -parse-as-library -typecheck \
  CineBar/Sources/CineBar/main.swift
for file in CineBar/Assets/Localization/*.lproj/Localizable.strings; do
  plutil -lint "$file"
done
```

Expected: regression executable passes, type-check passes, and every strings
file reports `OK`.

- [ ] **Step 7: Commit**

```bash
git add CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  CineBar/Assets/Localization
git commit -m "feat: add glass background opacity setting"
```

---

### Task 4: Add Permanent Movie and TV Short-Link Routes

**Files:**
- Create: `CineBarShare/tests/share-worker.test.mjs`
- Modify: `CineBarShare/worker.js`
- Modify: `CineBarShare/wrangler.jsonc`
- Modify: `CineBarShare/README.md`

**Interfaces:**
- Consumes: `env.TMDB_BEARER_TOKEN`, optional `env.CINEBAR_DOWNLOAD_URL`, and
  optional injected test fetcher `env.MEDIA_FETCHER`.
- Produces: `mediaPath(pathname) -> { mediaType, mediaID } | null`;
  public `GET /m/:id` and `GET /t/:id` HTML pages.

- [ ] **Step 1: Write failing short-route tests**

Create Node tests that import the Worker and verify:

```javascript
assert.deepEqual(mediaPath("/m/603"), {
  mediaType: "movie",
  mediaID: 603,
});
assert.deepEqual(mediaPath("/t/1399"), {
  mediaType: "tv",
  mediaID: 1399,
});
assert.equal(mediaPath("/m/not-a-number"), null);
```

Use `env.MEDIA_FETCHER` to return deterministic movie and TV JSON. Verify the
movie response contains `The Matrix`, the TV response contains `Game of
Thrones`, both responses contain canonical short `og:url` values, and neither
response reflects arbitrary query-string title or summary values.

- [ ] **Step 2: Add failing fallback and download tests**

Test these exact states:

```javascript
assert.doesNotMatch(htmlWithoutDownloadURL, /下载 CineBar for macOS/);
assert.match(htmlWithDownloadURL, /下载 CineBar for macOS/);
assert.match(htmlWithDownloadURL, /https:\/\/download\.example\/CineBar\.zip/);
assert.equal(fallbackResponse.status, 200);
assert.match(fallbackHTML, /电影 #603/);
```

The fallback fetcher must throw to simulate the upstream service being
unavailable.

- [ ] **Step 3: Run Worker tests and verify RED**

```bash
node --test CineBarShare/tests/share-worker.test.mjs
```

Expected: tests fail because `mediaPath`, `/m/:id`, `/t/:id`, metadata fetching,
and the optional download block do not exist.

- [ ] **Step 4: Implement strict routes and TMDB resolution**

Export `mediaPath` and accept only positive numeric IDs:

```javascript
export const mediaPath = (pathname) => {
  const match = pathname.match(/^\/(m|t)\/([1-9]\d*)\/?$/);
  if (!match) return null;
  return {
    mediaType: match[1] === "m" ? "movie" : "tv",
    mediaID: Number(match[2]),
  };
};
```

Fetch:

- movie: `https://api.themoviedb.org/3/movie/<id>?language=zh-CN`
- TV: `https://api.themoviedb.org/3/tv/<id>?language=zh-CN`

Send `Authorization: Bearer <env.TMDB_BEARER_TOKEN>` and
`Accept: application/json`. Map movie `title`/`release_date` and TV
`name`/`first_air_date` into one internal metadata shape. Use
`env.MEDIA_FETCHER ?? fetch` only as a test seam; never serialize it.

- [ ] **Step 5: Render canonical Open Graph data and fallback**

Render the canonical URL from `url.origin` plus `/m/:id` or `/t/:id`, ignoring
all title, rating, poster, and summary query parameters. Escape all metadata.
If the token is missing, the upstream response is non-2xx, JSON is invalid, or
the fetch throws, render HTTP 200 with `电影 #<id>` or `电视剧 #<id>`, the
CineBar logo, and a short temporary-unavailable message.

Append the download block only when `CINEBAR_DOWNLOAD_URL` parses as an
`https:` URL:

```html
<a class="download" href="...">下载 CineBar for macOS</a>
```

- [ ] **Step 6: Document deployment configuration**

Update `wrangler.jsonc` comments and `README.md` to document:

```bash
npx wrangler secret put TMDB_BEARER_TOKEN --name cinebar-share-test
npx wrangler deploy --name cinebar-share-test
```

Document `CINEBAR_DOWNLOAD_URL` as an optional Worker variable. Explain that it
must be omitted or left empty until a real HTTPS download page exists.

- [ ] **Step 7: Run Worker tests**

```bash
node --test CineBarShare/tests/share-worker.test.mjs
```

Expected: all route, metadata, fallback, canonical URL, escaping, and download
visibility tests pass.

- [ ] **Step 8: Commit**

```bash
git add CineBarShare
git commit -m "feat: add short branded share routes"
```

---

### Task 5: Share Readable Movie and TV Messages

**Files:**
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`
- Modify: `CineBar/Assets/Localization/zh-Hant.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/en.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ja.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ko.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `Movie`, `TVShow`, `CommunityRatingSummary?`, and the configured
  Share Worker root URL.
- Produces: `SharePayload.text`, `MovieStore.brandedShareURL(for:)` overloads
  for movie and TV, and an AppKit system-sharing action that receives
  `[String, URL]`.

- [ ] **Step 1: Add failing short-URL and message tests**

Configure a test `MovieStore` share root through a pure helper
`BrandedShareLink.url(baseURL:mediaType:mediaID:)` and add:

```swift
let movieURL = BrandedShareLink.url(
    baseURL: "https://share.example",
    mediaType: .movie,
    mediaID: 603
)
precondition(movieURL?.absoluteString == "https://share.example/m/603")

let tvURL = BrandedShareLink.url(
    baseURL: "https://share.example/",
    mediaType: .tv,
    mediaID: 1399
)
precondition(tvURL?.absoluteString == "https://share.example/t/1399")
precondition(movieURL?.query == nil)
precondition(tvURL?.query == nil)
```

Create a movie `SharePayload` with a CineBar score and a TV payload without
one. Verify the movie text contains the Chinese title, year, TMDB score,
`CineBar 8.6`, prompt, and short URL. Verify the TV text contains the TV icon
and prompt but does not contain `CineBar` in the score line when no community
average exists.

- [ ] **Step 2: Run Swift regression tests and verify RED**

Run the Task 3 Swift compile-and-run command.

Expected: compilation fails because `BrandedShareLink` and `SharePayload` do
not exist.

- [ ] **Step 3: Implement deterministic client short links**

Add:

```swift
enum BrandedShareLink {
    static func url(
        baseURL: String,
        mediaType: CommunityMediaType,
        mediaID: Int
    ) -> URL? {
        guard mediaID > 0,
              var components = URLComponents(string: baseURL) else {
            return nil
        }
        let root = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        let prefix = mediaType == .movie ? "m" : "t"
        components.path = "\(root)/\(prefix)/\(mediaID)"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
```

Replace the existing movie query-parameter URL builder and add the TV
overload.

- [ ] **Step 4: Implement share-text formatting**

Create `SharePayload` with `kind`, `title`, `year`, `tmdbScore`,
`cineBarScore`, and `url`. Its `text` must produce:

```text
🎬《<title>》（<year>）
⭐ TMDB <score>｜CineBar <score when present>
在 CineBar 查看简介、演员阵容与观看信息：
<short URL>
```

For TV, use `📺` and “在 CineBar 查看剧集资料与播出信息：”. Omit only the
CineBar score fragment when the community average is absent; keep the CineBar
brand in the prompt.

- [ ] **Step 5: Replace URL-only system sharing with AppKit item sharing**

Add a focused helper that presents:

```swift
let picker = NSSharingServicePicker(
    items: [payload.text as NSString, payload.url as NSURL]
)
```

Anchor it to the active main panel content view. The menu action must call this
helper so WeChat and other macOS sharing extensions receive both readable text
and the URL. Keep “复制分享文案”, X, and Weibo actions using the same
`SharePayload.text` so every share path stays consistent.

- [ ] **Step 6: Add TV sharing to the TV detail header**

Use the same reusable share menu for `TVShow`. Pass
`store.ratings(for: show)` or `store.communityRating?.averageScore` only for
the currently selected TV item. Place the share button beside the existing
reminder and watchlist controls.

- [ ] **Step 7: Add translations and run verification**

Add any new visible share labels and prompts to the four non-Simplified
Chinese localization files, then run:

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-test2-regression
/tmp/cinebar-test2-regression
xcrun swiftc -parse-as-library -typecheck \
  CineBar/Sources/CineBar/main.swift
for file in CineBar/Assets/Localization/*.lproj/Localizable.strings; do
  plutil -lint "$file"
done
```

Expected: Swift behavior tests and type-check pass; all localization files are
valid.

- [ ] **Step 8: Commit**

```bash
git add CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  CineBar/Assets/Localization
git commit -m "feat: share readable movie and TV messages"
```

---

### Task 6: Update Test Metadata, Documentation, Worker, and Universal Package

**Files:**
- Modify: `CineBar/Info.plist`
- Modify: `CineBar/README.md`
- Modify: `CineBar/请先阅读-测试版安装说明.html`
- Modify: `CineBar/请先阅读-测试版安装说明.txt`
- Modify: `CineBar/Tools/build_test_package.sh`
- Modify: `CineBarShare/worker.js`
- Create at build time: `dist/CineBar-0.8.1-test.2-universal.zip`

**Interfaces:**
- Consumes: completed Tasks 1–5 and an existing local TMDB bearer token for the
  Cloudflare secret.
- Produces: deployed `cinebar-share-test` Worker and the test.2 universal ZIP.

- [ ] **Step 1: Update version and release notes**

Set `CFBundleShortVersionString` to `0.8.1`, `CFBundleVersion` to `14`, and the
build script package name to `CineBar-0.8.1-test.2`. Update the Share Worker
manifest to:

```javascript
{
  version: "0.8.1",
  build: 14,
  published_at: "2026-07-27",
  download_url: null,
  notes: [
    "移除首次使用时不必要的钥匙串密码提示",
    "拆分地区分级与 CineBar 分级",
    "增加玻璃背景不透明度设置",
    "增加电影与电视剧短链接及完整分享文字",
  ],
}
```

- [ ] **Step 2: Update user documentation**

Document:

- test.2 and Build 14;
- no Mac login password is needed for CineBar’s anonymous identity;
- the first macOS Gatekeeper confirmation may still appear for an ad-hoc test
  build and is different from the removed Keychain password prompt;
- Appearance contains the 50%–100% background-only opacity slider;
- movie and TV shares include readable text plus permanent short links;
- the share-page download button stays hidden until a real download URL is
  configured;
- no GitHub upload or formal release is performed.

- [ ] **Step 3: Run all local automated checks**

```bash
node --test CineBarCommunity/tests/community-rating.test.mjs
node --test CineBarShare/tests/share-worker.test.mjs
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-test2-regression
/tmp/cinebar-test2-regression
xcrun swiftc -parse-as-library -typecheck \
  CineBar/Sources/CineBar/main.swift
plutil -lint CineBar/Info.plist
for file in CineBar/Assets/Localization/*.lproj/Localizable.strings; do
  plutil -lint "$file"
done
```

Expected: every test passes and every plist/strings file reports `OK`.

- [ ] **Step 4: Configure the Share Worker secret without printing it**

Verify the local CineBar TMDB token exists without displaying the value:

```bash
test -n "$(defaults read com.indiedev.cinebar tmdbToken 2>/dev/null)"
```

Then pipe it directly to Wrangler:

```bash
defaults read com.indiedev.cinebar tmdbToken 2>/dev/null |
  npx wrangler secret put TMDB_BEARER_TOKEN \
    --name cinebar-share-test
```

Do not put the token into `wrangler.jsonc`, Git, logs, documentation, or the
final response. If the local setting is absent, stop only this deployment step
and request the token through Wrangler’s interactive secret prompt; continue
all local build and verification work.

- [ ] **Step 5: Deploy and smoke-test the independent Share Worker**

```bash
cd CineBarShare
npx wrangler deploy --name cinebar-share-test
```

Verify:

```bash
curl -fsS https://cinebar-share-test.leeugm.workers.dev/m/603 |
  rg 'CineBar|Matrix|黑客帝国|og:url'
curl -fsS https://cinebar-share-test.leeugm.workers.dev/t/1399 |
  rg 'CineBar|Game of Thrones|权力的游戏|og:url'
```

Expected: both short routes return branded HTML and canonical Open Graph data.
Do not set `CINEBAR_DOWNLOAD_URL` until a genuine HTTPS download page exists.

- [ ] **Step 6: Build the universal package**

From the worktree root:

```bash
bash CineBar/Tools/build_test_package.sh
```

Expected:

`dist/CineBar-0.8.1-test.2-universal.zip`

- [ ] **Step 7: Verify the packaged application**

```bash
verification_dir=$(mktemp -d \
  "${TMPDIR:-/tmp}/cinebar-test2-verify.XXXXXX")
ditto -x -k \
  dist/CineBar-0.8.1-test.2-universal.zip \
  "$verification_dir"
packaged_app=$(find "$verification_dir" -type d -name CineBar.app \
  -print -quit)
test -n "$packaged_app"
unzip -l dist/CineBar-0.8.1-test.2-universal.zip |
  rg 'CineBar.app|请先阅读-测试版安装说明.html|请先阅读-测试版安装说明.txt'
file "$packaged_app/Contents/MacOS/CineBar"
lipo -archs "$packaged_app/Contents/MacOS/CineBar"
codesign --verify --deep --strict \
  "$packaged_app"
shasum -a 256 dist/CineBar-0.8.1-test.2-universal.zip
```

Expected architectures are `x86_64 arm64`, code-sign verification succeeds,
and a SHA-256 value is printed.

- [ ] **Step 8: Perform focused visual and interaction QA**

Open the packaged app on a dark or pure-black desktop and verify:

- 50%, 85%, and 100% settings visibly change only the main panel background;
- text, posters, buttons, and the Settings window do not fade;
- closing and reopening CineBar preserves the selected value;
- a rated movie and rated TV show display separate, equally sized official and
  CineBar classification cards;
- system sharing a movie and TV show previews readable text plus `/m/:id` or
  `/t/:id`, with no long query string;
- the share web page has no download button while its URL is unconfigured;
- a clean first launch does not ask for the login Keychain password.

- [ ] **Step 9: Inspect for secret leakage and commit the test package**

```bash
! rg -n 'TMDB_BEARER_TOKEN\\s*[=:]\\s*[A-Za-z0-9]' \
  CineBar CineBarShare
git diff --check
git status --short
```

Confirm no token value or Wrangler cache is staged. Then:

```bash
git add CineBar CineBarShare \
  dist/CineBar-0.8.1-test.2-universal.zip
git commit -m "build: package CineBar 0.8.1 test.2"
```

Do not push the branch and do not create a GitHub release.
