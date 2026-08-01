# CineBar Zero-Configuration Data Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver CineBar 0.8.2-test.1 Build 15 so users can browse TMDB data and view OMDb multi-ratings without supplying API keys or deploying services.

**Architecture:** Extend the existing `CineBarDataProxy` Worker with strict TMDB and OMDb routes, using encrypted Cloudflare Secrets and cache keys that never contain credentials. Embed the deployed proxy URL in the macOS client, make both data clients prefer it, and replace credential fields with a read-only built-in-service status while retaining legacy manual fields for unconfigured developer builds.

**Tech Stack:** Swift 6, SwiftUI, Foundation, Cloudflare Workers, Cache API, Node.js built-in test runner, Wrangler, TMDB API, OMDb API, universal arm64/x86_64 packaging.

## Global Constraints

- Target version is `0.8.2-test.1` with `CFBundleVersion` `15`.
- Users must not provide TMDB Token, OMDb Key, Cloudflare, D1, or community accounts.
- `TMDB_TOKEN` and `OMDB_API_KEY` are Cloudflare Secrets and never appear in source, Git, logs, URLs returned to clients, or installation packages.
- TMDB allows only `/trending/`, `/search/`, `/discover/`, `/movie/`, `/tv/`, `/person/`, and exact `/configuration/countries` GET paths.
- OMDb allows only `/omdb?i=tt<digits>` and rejects client-supplied `apikey` or free-form searches.
- Successful TMDB responses cache for 15 minutes; successful OMDb responses cache for 6 hours; failures do not cache.
- Existing community ratings, branded sharing, TVMaze, IMDb, Rotten Tomatoes, and Metacritic presentation remain available.
- The package is ad-hoc signed because no Apple Developer ID is available.
- The delivered ZIP contains `CineBar.app` plus detailed HTML and text installation instructions.
- Do not upload GitHub or create a GitHub Release.
- Do not add third-party dependencies.

---

### Task 1: Secure TMDB and OMDb Cloudflare Proxy

**Files:**
- Create: `CineBarDataProxy/tests/data-proxy.test.mjs`
- Modify: `CineBarDataProxy/worker.js`
- Modify: `CineBarDataProxy/wrangler.jsonc`
- Modify: `CineBarDataProxy/README.md`

**Interfaces:**
- Consumes: `env.TMDB_TOKEN`, `env.OMDB_API_KEY`, optional test seams
  `env.UPSTREAM_FETCHER` and `env.CACHE`, and `ctx.waitUntil(Promise)`.
- Produces: `tmdbPathAllowed(pathname) -> Bool`,
  `omdbIMDbID(url) -> String | null`, and Worker GET routes for TMDB and OMDb.

- [ ] **Step 1: Write failing route-validation tests**

Create Node tests that import `worker`, `tmdbPathAllowed`, and `omdbIMDbID`:

```javascript
assert.equal(tmdbPathAllowed("/movie/603"), true);
assert.equal(tmdbPathAllowed("/tv/1399/credits"), true);
assert.equal(tmdbPathAllowed("/configuration/countries"), true);
assert.equal(tmdbPathAllowed("/configuration/jobs"), false);
assert.equal(tmdbPathAllowed("/movie/../admin"), false);

assert.equal(
  omdbIMDbID(new URL("https://data.example/omdb?i=tt0133093")),
  "tt0133093",
);
assert.equal(
  omdbIMDbID(new URL("https://data.example/omdb?i=603")),
  null,
);
assert.equal(
  omdbIMDbID(
    new URL("https://data.example/omdb?i=tt0133093&apikey=stolen"),
  ),
  null,
);
```

- [ ] **Step 2: Write failing proxy behavior tests**

Use an in-memory cache with `match` and `put`, a recording upstream fetcher,
and a context whose `waitUntil` stores promises. Verify:

- `/movie/603?language=zh-CN` calls
  `https://api.themoviedb.org/3/movie/603?language=zh-CN`;
- TMDB authorization is `Bearer test-tmdb-secret`;
- `/omdb?i=tt0133093` calls OMDb with the server-side key;
- the incoming URL and cache keys never contain `test-omdb-secret`;
- the second identical request is served from cache;
- POST, invalid routes, invalid IMDb IDs, and client `apikey` return 404 or 400;
- missing secrets return 503;
- upstream failures use `cache-control: no-store`.

- [ ] **Step 3: Run tests and verify RED**

```bash
node --test CineBarDataProxy/tests/data-proxy.test.mjs
```

Expected: import or assertion failures because the exported validators and
OMDb route do not exist.

- [ ] **Step 4: Implement strict validators**

Export:

```javascript
const allowedPrefixes = [
  "/trending/",
  "/search/",
  "/discover/",
  "/movie/",
  "/tv/",
  "/person/",
];

export const tmdbPathAllowed = (pathname) =>
  !pathname.includes("..") &&
  (pathname === "/configuration/countries" ||
    allowedPrefixes.some((prefix) => pathname.startsWith(prefix)));

export const omdbIMDbID = (url) => {
  if (url.pathname !== "/omdb") return null;
  if ([...url.searchParams.keys()].some((key) => key !== "i")) return null;
  const imdbID = url.searchParams.get("i") ?? "";
  return /^tt\d{7,10}$/.test(imdbID) ? imdbID : null;
};
```

- [ ] **Step 5: Implement credential-free public cache keys**

For TMDB, use the incoming proxy URL as the cache key, call TMDB with an
Authorization header, and cache successful responses for 900 seconds.

For OMDb, use only `new Request(url.origin + "/omdb?i=" + imdbID)` as the
cache key, construct the upstream URL internally with `env.OMDB_API_KEY`, and
cache successful responses for 21,600 seconds.

Use:

```javascript
const fetcher = env.UPSTREAM_FETCHER ?? fetch;
const cache = env.CACHE ?? caches.default;
```

Set `x-content-type-options: nosniff`; set `cache-control: no-store` for every
non-success upstream response. Call `ctx.waitUntil(cache.put(...))` only after
successful responses.

- [ ] **Step 6: Update deployment configuration and documentation**

Declare required secrets in `wrangler.jsonc`:

```jsonc
"secrets": {
  "required": ["TMDB_TOKEN", "OMDB_API_KEY"]
}
```

Document these exact deployment commands:

```bash
npx wrangler secret put TMDB_TOKEN --name cinebar-data
npx wrangler secret put OMDB_API_KEY --name cinebar-data
npx wrangler deploy --name cinebar-data
```

Document the public routes and state that no key may be placed in `vars`.

- [ ] **Step 7: Run Data Proxy tests and dry-run build**

```bash
node --test CineBarDataProxy/tests/data-proxy.test.mjs
cd CineBarDataProxy
npx wrangler deploy --dry-run --outdir /tmp/cinebar-data-dry-run
```

Expected: every Node test passes and Wrangler reports both required secrets
without uploading.

- [ ] **Step 8: Commit**

```bash
git add CineBarDataProxy
git commit -m "feat: proxy TMDB and OMDb data securely"
```

---

### Task 2: Make the macOS Client Prefer the Built-In Data Service

**Files:**
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`
- Modify: `CineBar/Info.plist`

**Interfaces:**
- Consumes: `CineBarDataProxyURL`.
- Produces: `DataProxyConfiguration.normalizedBaseURL(_:)`,
  `OMDbEndpoint.url(proxyBaseURL:apiKey:imdbID:)`,
  `DataSettingsPresentation.usesBuiltInService`,
  and proxy-aware `OMDbClient`.

- [ ] **Step 1: Add failing endpoint tests**

Add:

```swift
precondition(
    DataProxyConfiguration.normalizedBaseURL(
        "https://cinebar-data.leeugm.workers.dev/"
    ) == "https://cinebar-data.leeugm.workers.dev"
)
precondition(
    DataProxyConfiguration.normalizedBaseURL("ftp://invalid") == nil
)

let proxiedOMDbURL = OMDbEndpoint.url(
    proxyBaseURL: "https://cinebar-data.leeugm.workers.dev",
    apiKey: "",
    imdbID: "tt0133093"
)
precondition(
    proxiedOMDbURL?.absoluteString ==
        "https://cinebar-data.leeugm.workers.dev/omdb?i=tt0133093"
)
precondition(
    !proxiedOMDbURL!.absoluteString.contains("apikey")
)
```

Also verify a legacy developer build with no proxy still generates the direct
OMDb URL only when a non-empty API key is provided.

- [ ] **Step 2: Run Swift tests and verify RED**

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-zero-config-regression
/tmp/cinebar-zero-config-regression
```

Expected: compilation fails because the configuration and endpoint helpers do
not exist.

- [ ] **Step 3: Implement URL helpers**

Add:

```swift
enum DataProxyConfiguration {
    static func normalizedBaseURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.hasPrefix("https://") ||
                cleaned.hasPrefix("http://localhost") else {
            return nil
        }
        return cleaned.hasSuffix("/")
            ? String(cleaned.dropLast())
            : cleaned
    }
}
```

Add `OMDbEndpoint.url(...)` so a valid proxy always wins and produces only
`/omdb?i=<IMDb ID>`. Without a proxy, it may produce the legacy
`https://www.omdbapi.com/?apikey=<key>&i=<IMDb ID>` URL for developer builds.
Reject invalid IMDb IDs before constructing either URL.

- [ ] **Step 4: Route OMDbClient through the proxy**

Change `OMDbClient` to:

```swift
struct OMDbClient {
    let apiKey: String
    let proxyBaseURL: String?

    func ratings(imdbID: String) async throws -> [MovieRating] {
        guard let url = OMDbEndpoint.url(
            proxyBaseURL: proxyBaseURL,
            apiKey: apiKey,
            imdbID: imdbID
        ) else {
            throw CineBarError.server(
                "CineBar 数据服务暂时不可用，请稍后重试"
            )
        }
        // Keep the existing response decoding and source mapping.
    }
}
```

Pass `dataProxyURL` from `MovieStore.loadExternalRatings`. Change
`hasOMDbKey` to return true when either a proxy is configured or a legacy local
key exists. Reuse `DataProxyConfiguration` in both `TMDBClient` and
`MovieStore.hasDataProxy` so the two clients make the same decision.

- [ ] **Step 5: Add and test read-only presentation policy**

Add:

```swift
struct DataSettingsPresentation {
    let usesBuiltInService: Bool
    var showsCredentialFields: Bool { !usesBuiltInService }
    var showsCredentialLinks: Bool { !usesBuiltInService }
}
```

Test both true and false states in `RegressionBehaviorTests.swift`.

- [ ] **Step 6: Configure the deployed proxy URL**

Set:

```xml
<key>CineBarDataProxyURL</key>
<string>https://cinebar-data.leeugm.workers.dev</string>
```

Do not place either upstream key in `Info.plist`.

- [ ] **Step 7: Run Swift verification**

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-zero-config-regression
/tmp/cinebar-zero-config-regression
xcrun swiftc -parse-as-library -typecheck \
  CineBar/Sources/CineBar/main.swift
plutil -lint CineBar/Info.plist
```

Expected: behavior tests, type-check, and plist validation pass.

- [ ] **Step 8: Commit**

```bash
git add CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift CineBar/Info.plist
git commit -m "feat: use built-in movie data service"
```

---

### Task 3: Replace Credential UI with Read-Only Data Status

**Files:**
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Assets/Localization/zh-Hant.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/en.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ja.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ko.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `DataSettingsPresentation(usesBuiltInService:)`.
- Produces: a zero-configuration read-only status card while preserving legacy
  credential fields only when no proxy exists.

- [ ] **Step 1: Implement the explicit settings branches**

In `dataSettings`, create:

```swift
let presentation = DataSettingsPresentation(
    usesBuiltInService: store.hasDataProxy
)
```

When `presentation.usesBuiltInService` is true, show a green
“CineBar 内置数据服务已启用” label and three rows:

- `TMDB` — “电影、电视剧、演员、海报及观看平台”
- `OMDb` — “IMDb、烂番茄和 Metacritic 多重评分”
- `TVMaze` — “电视剧下一集播出时间”

Do not instantiate either `SecureField` or either API application `Link` in
this branch. When false, retain both legacy fields and links for local
developer builds. Keep the viewing-region picker and Save/Refresh button in
both branches.

- [ ] **Step 2: Add all new localizations**

Add the built-in service label and three source descriptions to Traditional
Chinese, English, Japanese, and Korean. Use the existing Simplified Chinese
keys as source language.

- [ ] **Step 3: Validate source structure and localization**

```bash
rg -n 'DataSettingsPresentation|CineBar 内置数据服务已启用' \
  CineBar/Sources/CineBar/main.swift
for file in CineBar/Assets/Localization/*.lproj/Localizable.strings; do
  plutil -lint "$file"
done
xcrun swiftc -parse-as-library -typecheck \
  CineBar/Sources/CineBar/main.swift
```

Expected: source contains the explicit policy, all localization files report
`OK`, and Swift type-check passes.

- [ ] **Step 4: Commit**

```bash
git add CineBar/Sources/CineBar/main.swift CineBar/Assets/Localization
git commit -m "feat: show built-in data service status"
```

---

### Task 4: Deploy, Version, Document, and Package Build 15

**Files:**
- Modify: `CineBar/Info.plist`
- Modify: `CineBar/README.md`
- Modify: `CineBar/请先阅读-测试版安装说明.html`
- Modify: `CineBar/请先阅读-测试版安装说明.txt`
- Modify: `CineBar/Tools/build_test_package.sh`
- Modify: `CineBarShare/worker.js`
- Create at build time: `dist/CineBar-0.8.2-test.1-universal.zip`

**Interfaces:**
- Consumes: local TMDB and OMDb values already saved in CineBar preferences,
  Cloudflare account login, and completed Tasks 1–3.
- Produces: deployed `cinebar-data`, updated test Share manifest, and the
  universal zero-configuration ZIP.

- [ ] **Step 1: Update version metadata and release notes**

Set:

- `CFBundleShortVersionString` to `0.8.2`;
- `CFBundleVersion` to `15`;
- build script package name to `CineBar-0.8.2-test.1`;
- Share manifest version to `0.8.2`, build to `15`, and notes to:

```javascript
[
  "用户无需申请或填写 TMDB Token",
  "OMDb 多重评分改用 CineBar 后台代理",
  "数据来源页面改为内置服务状态",
  "继续保留 IMDb、烂番茄和 Metacritic 评分",
]
```

- [ ] **Step 2: Update documentation**

State clearly that:

- no API key, Cloudflare, D1, or account setup is required;
- TMDB and OMDb are provided through CineBar’s developer-operated service;
- the build remains unnotarized and requires the macOS first-open security
  confirmation;
- community ratings and branded sharing are already configured;
- the package is not uploaded to GitHub.

- [ ] **Step 3: Run all local automated checks**

```bash
node --test CineBarCommunity/tests/community-rating.test.mjs
node --test CineBarShare/tests/share-worker.test.mjs
node --test CineBarDataProxy/tests/data-proxy.test.mjs
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-zero-config-regression
/tmp/cinebar-zero-config-regression
xcrun swiftc -parse-as-library -typecheck \
  CineBar/Sources/CineBar/main.swift
plutil -lint CineBar/Info.plist
for file in CineBar/Assets/Localization/*.lproj/Localizable.strings; do
  plutil -lint "$file"
done
```

Expected: every test passes and every plist/strings file reports `OK`.

- [ ] **Step 4: Upload both Data Proxy secrets without displaying them**

Verify the values exist without printing them, then pipe them directly:

```bash
defaults read com.indiedev.cinebar tmdbToken 2>/dev/null |
  npx wrangler secret put TMDB_TOKEN --name cinebar-data
defaults read com.indiedev.cinebar omdbKey 2>/dev/null |
  npx wrangler secret put OMDB_API_KEY --name cinebar-data
```

Run from `CineBarDataProxy`. Do not echo, log, copy into a file, or include
either value in the final response.

- [ ] **Step 5: Deploy Data Proxy and updated Share manifest**

```bash
cd CineBarDataProxy
npx wrangler deploy --name cinebar-data
cd ../CineBarShare
npx wrangler deploy --name cinebar-share-test
```

Expected service roots:

- `https://cinebar-data.leeugm.workers.dev`
- `https://cinebar-share-test.leeugm.workers.dev`

- [ ] **Step 6: Smoke-test real data without exposing credentials**

Verify in a browser:

- `/movie/603?language=zh-CN` returns TMDB movie ID 603 and a localized title;
- `/omdb?i=tt0133093` returns `Response: "True"` and rating entries;
- `/omdb?i=invalid` is rejected;
- no response URL, visible page, or error contains `apikey`.

- [ ] **Step 7: Build the universal ZIP**

```bash
bash CineBar/Tools/build_test_package.sh
```

Expected:

`dist/CineBar-0.8.2-test.1-universal.zip`

- [ ] **Step 8: Verify the package**

```bash
verification_dir=$(mktemp -d \
  "${TMPDIR:-/tmp}/cinebar-zero-config.XXXXXX")
ditto -x -k dist/CineBar-0.8.2-test.1-universal.zip \
  "$verification_dir"
packaged_app=$(find "$verification_dir" -type d -name CineBar.app \
  -print -quit)
test -n "$packaged_app"
test "$(lipo -archs "$packaged_app/Contents/MacOS/CineBar")" \
  = "x86_64 arm64"
codesign --verify --deep --strict "$packaged_app"
test "$(plutil -extract CFBundleVersion raw \
  "$packaged_app/Contents/Info.plist")" = "15"
test "$(plutil -extract CineBarDataProxyURL raw \
  "$packaged_app/Contents/Info.plist")" \
  = "https://cinebar-data.leeugm.workers.dev"
shasum -a 256 dist/CineBar-0.8.2-test.1-universal.zip
```

Also verify one HTML and one text installation guide are present next to the
app in the extracted folder.

- [ ] **Step 9: Scan for leaked secrets and commit**

```bash
! rg -n 'TMDB_TOKEN\\s*[=:]\\s*[A-Za-z0-9]|OMDB_API_KEY\\s*[=:]\\s*[A-Za-z0-9]' \
  CineBar CineBarDataProxy CineBarShare
git diff --check
git add CineBar CineBarDataProxy CineBarShare/worker.js \
  dist/CineBar-0.8.2-test.1-universal.zip
git commit -m "build: package CineBar zero-configuration test release"
```

Do not push and do not create a GitHub release.
