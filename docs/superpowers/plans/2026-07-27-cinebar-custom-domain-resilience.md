# CineBar Custom Domain Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver CineBar 0.8.2-test.2 Build 16 with `cinebar.cc` production-style service endpoints, retry and cached-data degradation, health checks, and no client dependency on `workers.dev`.

**Architecture:** Register `cinebar.cc` through the existing Cloudflare account, map independent Custom Domains to the existing data, community, and share Workers, and keep `api-hk.cinebar.cc` unconfigured until a real Hong Kong backend exists. Add a small reusable Swift networking layer that retries only transport and server failures, supports an empty backup list today, redacts diagnostics, and falls back to the last successful real browse data before using packaged demo content.

**Tech Stack:** Swift 6, SwiftUI, Foundation `URLSession`, UserDefaults JSON cache, Cloudflare Workers, Worker Custom Domains, D1, Node.js built-in test runner, Wrangler 4, universal arm64/x86_64 packaging.

## Global Constraints

- Domain is exactly `cinebar.cc`, purchased from Cloudflare Registrar only after a fresh authoritative availability and price check.
- Approved price ceiling is 8.00 USD for the first year; stop before purchase if the displayed charge exceeds 8.00 USD or adds an unexpected recurring product.
- Domain registration is non-refundable; the user enters and confirms legal contact, payment, and agreement information.
- Public service endpoints are exactly `https://api.cinebar.cc`, `https://community.cinebar.cc`, and `https://share.cinebar.cc`.
- `https://cinebar.cc` is a lightweight brand/status page only in this release.
- `api-hk.cinebar.cc` remains absent from DNS and the client backup list until a real Hong Kong service exists.
- Do not disable ATS, bypass certificate validation, install a root certificate, change user DNS, or require a proxy/VPN.
- Do not expose TMDB, OMDb, community secrets, D1 data, device identifiers, or account details in health responses or diagnostics.
- Existing `workers.dev` deployments may remain for maintenance, but the built client, package instructions, and public user flows must not reference them.
- Retry DNS, TLS, connection, interruption, timeout, and HTTP 5xx failures only; never retry or fail over HTTP 4xx.
- Retry each endpoint at most once, for a maximum of two attempts per endpoint.
- Show last successful real browse data after a network failure; use demo data only if no successful cache exists.
- Target package is `CineBar-0.8.2-test.2-universal.zip`, `CFBundleShortVersionString` `0.8.2`, and `CFBundleVersion` `16`.
- Do not upload GitHub or create a GitHub Release in this network-fix cycle.
- Defer upcoming-date labels, system-share renaming, cast on share pages, and the GitHub download entry.

---

## File Structure

- `CineBarDataProxy/worker.js`: data proxy routes and data-service health response.
- `CineBarDataProxy/tests/data-proxy.test.mjs`: data health and existing proxy security tests.
- `CineBarDataProxy/wrangler.jsonc`: `api.cinebar.cc` Custom Domain.
- `CineBarCommunity/worker.js`: rating API and community-service health response.
- `CineBarCommunity/tests/community-rating.test.mjs`: community health and rating tests.
- `CineBarCommunity/wrangler.toml`: `community.cinebar.cc` Custom Domain and D1 binding.
- `CineBarCommunity/wrangler.toml.example`: redacted example with the same public route.
- `CineBarShare/worker.js`: share/update routes, share-service health response, and lightweight root brand page.
- `CineBarShare/tests/share-worker.test.mjs`: health, root page, share, and update tests.
- `CineBarShare/wrangler.jsonc`: `share.cinebar.cc` and `cinebar.cc` Custom Domains.
- `CineBar/Sources/CineBar/ServiceNetworking.swift`: endpoint configuration, retry classification, redacted diagnostics, and injected-session resilient HTTP transport.
- `CineBar/Sources/CineBar/main.swift`: service integration, browse cache usage, and settings diagnostics UI.
- `CineBar/Tests/RegressionBehaviorTests.swift`: endpoint, retry, cache, and presentation regression coverage.
- `CineBar/Info.plist`: three custom-domain URLs, empty backup arrays, and Build 16 metadata.
- `CineBar/Tools/build_test_package.sh`: compile every Swift source file and produce test.2.
- `CineBar/README.md`: zero-configuration custom-domain behavior and network limitations.
- `CineBar/请先阅读-测试版安装说明.html`: end-user installation and network behavior.
- `CineBar/请先阅读-测试版安装说明.txt`: plain-text equivalent.
- `dist/CineBar-0.8.2-test.2-universal.zip`: verified delivery artifact.

---

### Task 1: Purchase and Activate `cinebar.cc`

**Files:**
- No repository files change in this task.

**Interfaces:**
- Consumes: Cloudflare account `Leeugm@gmail.com's Account`, approved domain `cinebar.cc`, and 8.00 USD price ceiling.
- Produces: active Cloudflare Registrar registration and active Cloudflare zone for `cinebar.cc`.

- [ ] **Step 1: Perform a fresh read-only availability and price check**

Open:

`https://dash.cloudflare.com/0e298d7ba2baffcec95e0e2e5d643244/domains/registrations/purchase?query=cinebar.cc`

Verify all four conditions:

- exact domain is `cinebar.cc`;
- available for registration;
- first-year charge is 8.00 USD;
- renewal is 8.00 USD.

Stop without purchasing if the domain is premium, unavailable, or the immediate charge exceeds 8.00 USD.

- [ ] **Step 2: Create the Cloudflare default registrant contact**

Use Cloudflare **Create default contact**. Hand control to the user to enter their real registrant name, address, phone number, and email. Do not copy these values into logs, source files, chat output, or the plan.

- [ ] **Step 3: Confirm the payment method**

Open Cloudflare billing payment information. Hand control to the user if a payment method must be entered, updated, saved, or verified. Do not read or repeat card details.

- [ ] **Step 4: Review the final order**

At the final review screen verify:

- one domain only: `cinebar.cc`;
- one-year registration;
- auto-renew enabled;
- no email, hosting, Enterprise, China Network, or other paid add-on;
- total immediate charge no more than 8.00 USD.

- [ ] **Step 5: Complete the purchase with the user**

Because registration is non-refundable and may require agreement acceptance, hand control to the user for the final purchase/terms action. Resume only after the dashboard confirms successful registration.

- [ ] **Step 6: Verify activation**

Open Cloudflare **Domains → Overview** and verify `cinebar.cc` is active in account `0e298d7ba2baffcec95e0e2e5d643244`. Record only the domain status, not registrant or billing data.

---

### Task 2: Add Health Endpoints and Custom Domain Configuration

**Files:**
- Modify: `CineBarDataProxy/tests/data-proxy.test.mjs`
- Modify: `CineBarDataProxy/worker.js`
- Modify: `CineBarDataProxy/wrangler.jsonc`
- Modify: `CineBarCommunity/tests/community-rating.test.mjs`
- Modify: `CineBarCommunity/worker.js`
- Modify: `CineBarCommunity/wrangler.toml`
- Modify: `CineBarCommunity/wrangler.toml.example`
- Modify: `CineBarShare/tests/share-worker.test.mjs`
- Modify: `CineBarShare/worker.js`
- Modify: `CineBarShare/wrangler.jsonc`

**Interfaces:**
- Consumes: active `cinebar.cc` zone and current Workers.
- Produces: `healthResponse(service, version) -> Response` behavior on each Worker and deployable Custom Domain route declarations.

- [ ] **Step 1: Write failing data-service health tests**

Add to `CineBarDataProxy/tests/data-proxy.test.mjs`:

```javascript
test("reports data service health without calling an upstream", async () => {
  let upstreamCalls = 0;
  const response = await worker.fetch(
    new Request("https://api.cinebar.cc/health"),
    {
      UPSTREAM_FETCHER: async () => {
        upstreamCalls += 1;
        throw new Error("must not be called");
      },
    },
    context(),
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.service, "cinebar-data");
  assert.equal(body.version, "0.8.2-test.2");
  assert.match(body.utc, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(upstreamCalls, 0);
  assert.equal(JSON.stringify(body).includes("TOKEN"), false);
  assert.equal(response.headers.get("cache-control"), "no-store");
});
```

- [ ] **Step 2: Write failing community-service health tests**

Add to `CineBarCommunity/tests/community-rating.test.mjs`:

```javascript
test("reports community service health without querying D1", async () => {
  const response = await worker.fetch(
    new Request("https://community.cinebar.cc/health"),
    {},
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.service, "cinebar-community");
  assert.equal(body.version, "0.8.2-test.2");
  assert.match(body.utc, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(response.headers.get("cache-control"), "no-store");
});
```

- [ ] **Step 3: Write failing share-service health and root-page tests**

Add to `CineBarShare/tests/share-worker.test.mjs`:

```javascript
test("reports share service health", async () => {
  const response = await fetchPage("/health");
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.service, "cinebar-share");
  assert.equal(body.version, "0.8.2-test.2");
  assert.match(body.utc, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(response.headers.get("cache-control"), "no-store");
});

test("renders a lightweight CineBar root page", async () => {
  const response = await fetchPage("/");
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.match(html, /CineBar/);
  assert.match(html, /今晚看什么/);
  assert.doesNotMatch(html, /github\.com|下载 CineBar/);
});
```

- [ ] **Step 4: Run Worker tests and verify RED**

Run:

```bash
node --test CineBarDataProxy/tests/data-proxy.test.mjs
node --test CineBarCommunity/tests/community-rating.test.mjs
node --test CineBarShare/tests/share-worker.test.mjs
```

Expected: health assertions fail because the routes do not exist; the share root-page assertion also fails.

- [ ] **Step 5: Implement one minimal health response per Worker**

In each Worker, handle `/health` before any secret, upstream, or D1 validation:

```javascript
const healthResponse = (service) => new Response(
  JSON.stringify({
    ok: true,
    service,
    version: "0.8.2-test.2",
    utc: new Date().toISOString(),
  }),
  {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  },
);
```

Use service values `cinebar-data`, `cinebar-community`, and `cinebar-share`. Add a minimal branded HTML response for `/` in the Share Worker only. It must not include a download button or GitHub link in this cycle.

- [ ] **Step 6: Add exact Custom Domain routes**

Add to `CineBarDataProxy/wrangler.jsonc`:

```jsonc
"routes": [
  { "pattern": "api.cinebar.cc", "custom_domain": true }
]
```

Add to both community TOML files:

```toml
[[routes]]
pattern = "community.cinebar.cc"
custom_domain = true
```

Set the Share Worker name to the deployed test Worker and add both hostnames:

```jsonc
"name": "cinebar-share-test",
"routes": [
  { "pattern": "share.cinebar.cc", "custom_domain": true },
  { "pattern": "cinebar.cc", "custom_domain": true }
]
```

Do not add `api-hk.cinebar.cc`.

- [ ] **Step 7: Run Worker tests and Wrangler dry runs**

Run:

```bash
node --test CineBarDataProxy/tests/data-proxy.test.mjs
node --test CineBarCommunity/tests/community-rating.test.mjs
node --test CineBarShare/tests/share-worker.test.mjs
(cd CineBarDataProxy && npx wrangler deploy --dry-run --outdir /tmp/cinebar-data-domain-dry)
(cd CineBarCommunity && npx wrangler deploy --dry-run --outdir /tmp/cinebar-community-domain-dry)
(cd CineBarShare && npx wrangler deploy --dry-run --outdir /tmp/cinebar-share-domain-dry)
```

Expected: all Node tests pass and all three dry runs exit 0 without uploading.

- [ ] **Step 8: Commit**

```bash
git add CineBarDataProxy CineBarCommunity CineBarShare
git commit -m "feat: prepare CineBar custom service domains"
```

---

### Task 3: Build a Tested Resilient Swift Transport

**Files:**
- Create: `CineBar/Sources/CineBar/ServiceNetworking.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`
- Modify: `CineBar/Tools/build_test_package.sh`

**Interfaces:**
- Consumes: primary and optional backup endpoint strings from `Info.plist`.
- Produces:
  - `ServiceEndpointSet.init(primary:backups:)`
  - `ServiceRequestPolicy.isRetryable(error:) -> Bool`
  - `ServiceRequestPolicy.isRetryable(statusCode:) -> Bool`
  - `ServiceRequestPolicy.attemptsPerEndpoint == 2`
  - `ServiceDiagnostic.redactedText`
  - `ResilientHTTPClient.data(endpointSet:buildRequest:) async throws -> (Data, HTTPURLResponse)`

- [ ] **Step 1: Add failing endpoint and retry-classification tests**

At the start of `CineBarRegressionBehaviorTests.main()` add:

```swift
let endpoints = ServiceEndpointSet(
    primary: "https://api.cinebar.cc/",
    backups: ["", "ftp://invalid", "https://api-hk.cinebar.cc/"]
)
precondition(
    endpoints.urls.map(\.absoluteString) == [
        "https://api.cinebar.cc",
        "https://api-hk.cinebar.cc"
    ]
)
precondition(ServiceRequestPolicy.attemptsPerEndpoint == 2)
precondition(
    ServiceRequestPolicy.isRetryable(
        error: URLError(.secureConnectionFailed)
    )
)
precondition(
    ServiceRequestPolicy.isRetryable(
        error: URLError(.cannotFindHost)
    )
)
precondition(
    ServiceRequestPolicy.isRetryable(
        error: URLError(.timedOut)
    )
)
precondition(ServiceRequestPolicy.isRetryable(statusCode: 503))
precondition(!ServiceRequestPolicy.isRetryable(statusCode: 404))
```

- [ ] **Step 2: Add failing diagnostic redaction tests**

Add:

```swift
let diagnostic = ServiceDiagnostic(
    service: "data",
    category: .tls,
    timestamp: Date(timeIntervalSince1970: 0),
    appVersion: "0.8.2 (16)",
    requestURL: URL(
        string: "https://api.cinebar.cc/omdb?i=tt0133093&apikey=secret"
    )!
)
precondition(diagnostic.redactedText.contains("api.cinebar.cc"))
precondition(!diagnostic.redactedText.contains("apikey"))
precondition(!diagnostic.redactedText.contains("secret"))
precondition(!diagnostic.redactedText.contains("tt0133093"))
```

- [ ] **Step 3: Run Swift tests and verify RED**

Run:

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-domain-regression
```

Expected: compilation fails because the new networking types do not exist.

- [ ] **Step 4: Implement endpoint normalization and retry rules**

Create `ServiceNetworking.swift` with:

```swift
import Foundation

struct ServiceEndpointSet {
    let urls: [URL]

    init(primary: String?, backups: [String]) {
        let values = [primary ?? ""] + backups
        var seen = Set<String>()
        urls = values.compactMap {
            DataProxyConfiguration.normalizedBaseURL($0)
        }
        .filter { seen.insert($0).inserted }
        .compactMap(URL.init(string:))
    }
}

enum ServiceFailureCategory: String {
    case dns, tls, connection, timeout, server, client, other
}

enum ServiceRequestPolicy {
    static let attemptsPerEndpoint = 2

    static func isRetryable(error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [
            .cannotFindHost,
            .dnsLookupFailed,
            .secureConnectionFailed,
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .cannotConnectToHost,
            .networkConnectionLost,
            .timedOut,
        ].contains(error.code)
    }

    static func isRetryable(statusCode: Int) -> Bool {
        (500...599).contains(statusCode)
    }
}
```

`ServiceDiagnostic.redactedText` may include the URL scheme and host, but never path, query, fragment, headers, body, device ID, or underlying error debug dictionary.

- [ ] **Step 5: Add an injected-session transport and its deterministic test seam**

Define:

```swift
protocol ServiceDataLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: ServiceDataLoading {}

struct ResilientHTTPClient {
    let loader: ServiceDataLoading

    func data(
        endpointSet: ServiceEndpointSet,
        buildRequest: (URL) throws -> URLRequest
    ) async throws -> (Data, HTTPURLResponse)
}
```

For each endpoint, attempt exactly twice. Continue to the next endpoint only for `ServiceRequestPolicy` retryable errors or 5xx. Return immediately for 2xx. Throw immediately for 4xx. Preserve the last retryable error after exhausting all candidates.

Add a `RecordingServiceLoader` in the regression test that returns:

1. `URLError(.secureConnectionFailed)`;
2. HTTP 503;
3. HTTP 200 with `{}`.

Verify the loader records three calls and reaches the backup host. Add a second loader returning HTTP 404 first and verify it records one call only.

- [ ] **Step 6: Update build commands for multiple Swift files**

In `build_test_package.sh`, replace the single source variable with:

```bash
source_dir="$app_source_dir/Sources/CineBar"
swift_sources=("$source_dir"/*.swift)
```

Pass `"${swift_sources[@]}"` to both `swiftc` commands. Update every regression and typecheck command in the README or plan-driven scripts to use `CineBar/Sources/CineBar/*.swift`.

- [ ] **Step 7: Run Swift tests and typecheck**

Run:

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-domain-regression
/tmp/cinebar-domain-regression
xcrun swiftc -parse-as-library -typecheck \
  CineBar/Sources/CineBar/*.swift
```

Expected: compile, regression execution, and typecheck all exit 0.

- [ ] **Step 8: Commit**

```bash
git add CineBar/Sources/CineBar/ServiceNetworking.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  CineBar/Tools/build_test_package.sh
git commit -m "feat: add resilient CineBar service transport"
```

---

### Task 4: Integrate Custom Endpoints, Cached Real Data, and Diagnostics

**Files:**
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Sources/CineBar/ServiceNetworking.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`
- Modify: `CineBar/Info.plist`
- Modify: `CineBar/Assets/Localization/en.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ja.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ko.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/zh-Hant.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `ResilientHTTPClient`, three primary bundle URLs, and three empty backup URL arrays.
- Produces:
  - `LastSuccessfulBrowseCache.saveMovies/loadMovies`
  - `LastSuccessfulBrowseCache.saveTelevision/loadTelevision`
  - retry-aware TMDB, OMDb, community, update, and share-service callers
  - localized cached-content warning and copyable redacted diagnostics.

- [ ] **Step 1: Add failing browse-cache tests**

Add to `RegressionBehaviorTests.swift`:

```swift
let cacheSuite = "CineBarBrowseCacheTests.\(UUID().uuidString)"
let cacheDefaults = UserDefaults(suiteName: cacheSuite)!
cacheDefaults.removePersistentDomain(forName: cacheSuite)
let browseCache = LastSuccessfulBrowseCache(defaults: cacheDefaults)

browseCache.saveMovies(Movie.demo)
precondition(browseCache.loadMovies() == Movie.demo)
browseCache.saveTelevision([TVShow.demo])
precondition(browseCache.loadTelevision() == [TVShow.demo])

cacheDefaults.set(Data("invalid".utf8), forKey: "lastSuccessfulMovies")
precondition(browseCache.loadMovies() == nil)
cacheDefaults.removePersistentDomain(forName: cacheSuite)
```

- [ ] **Step 2: Add failing presentation tests**

Add:

```swift
precondition(
    ServiceErrorPresentation.message(
        language: .zhCN,
        hasCachedContent: true
    ) == "网络不稳定，正在显示上次更新内容"
)
precondition(
    ServiceErrorPresentation.message(
        language: .enUS,
        hasCachedContent: false
    ).contains("temporarily unavailable")
)
```

- [ ] **Step 3: Run Swift regression tests and verify RED**

Run the Task 3 regression compile command.

Expected: compilation fails because the browse cache and presentation types do not exist.

- [ ] **Step 4: Implement the bounded UserDefaults browse cache**

In `ServiceNetworking.swift`, implement:

```swift
struct LastSuccessfulBrowseCache {
    let defaults: UserDefaults

    func saveMovies(_ movies: [Movie])
    func loadMovies() -> [Movie]?
    func saveTelevision(_ shows: [TVShow])
    func loadTelevision() -> [TVShow]?
}
```

Use `JSONEncoder` and `JSONDecoder`. Save only non-empty successful browse arrays. If decoding fails, remove that corrupt cache key and return `nil`. Do not cache community device IDs, rating submissions, tokens, trailers, or personal watchlists in these keys.

- [ ] **Step 5: Embed exact primary endpoints and empty backup arrays**

Set in `Info.plist`:

```xml
<key>CineBarDataProxyURL</key>
<string>https://api.cinebar.cc</string>
<key>CineBarDataBackupURLs</key>
<array/>
<key>CineBarCommunityURL</key>
<string>https://community.cinebar.cc</string>
<key>CineBarCommunityBackupURLs</key>
<array/>
<key>CineBarShareURL</key>
<string>https://share.cinebar.cc</string>
<key>CineBarShareBackupURLs</key>
<array/>
<key>CineBarUpdateManifestURL</key>
<string>https://share.cinebar.cc/updates/latest.json</string>
```

Do not add `api-hk.cinebar.cc`.

- [ ] **Step 6: Integrate the resilient transport**

Replace direct data calls in:

- `TMDBClient`;
- `OMDbClient`;
- `CommunityRatingClient`;
- update-manifest checking.

Each client builds a request from the candidate base URL passed by `ResilientHTTPClient`. Preserve current authorization rules: the TMDB and OMDb client never adds user credentials when a built-in proxy is configured.

Share URLs are generated directly from `https://share.cinebar.cc`; they are not retried by the app because the receiving browser owns that navigation.

- [ ] **Step 7: Save successful browse results and degrade in the correct order**

In successful movie and television browse loads, save non-empty results to `LastSuccessfulBrowseCache`.

In each corresponding failure branch:

1. load last successful content;
2. if present, show it and set the localized cached-content warning;
3. otherwise use the existing demo content and a localized temporary-unavailable message.

Do not overwrite cached real data with demo content or an empty server response.

- [ ] **Step 8: Add redacted diagnostics to Data Sources settings**

Store only the most recent `ServiceDiagnostic`. In Data Sources settings add:

- service state text;
- localized friendly error category;
- **Copy diagnostics** button when a diagnostic exists.

The copied text contains app version, UTC time, service label, error category, and scheme/host. It must not contain URL path, query, request body, header, API key, device ID, email, IP address, or D1 information.

- [ ] **Step 9: Add translations**

Add translations for:

- `网络不稳定，正在显示上次更新内容`
- `服务暂时不可用，请稍后重试`
- `复制诊断信息`
- `诊断信息已复制`
- `数据服务`
- `社区评分服务`
- `分享与更新服务`

to English, Japanese, Korean, and Traditional Chinese string files. Simplified Chinese uses source text.

- [ ] **Step 10: Run regression, typecheck, plist, and localization checks**

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-domain-regression
/tmp/cinebar-domain-regression
xcrun swiftc -parse-as-library -typecheck CineBar/Sources/CineBar/*.swift
plutil -lint CineBar/Info.plist
for file in CineBar/Assets/Localization/*.lproj/Localizable.strings; do
  plutil -lint "$file"
done
```

Expected: all commands exit 0.

- [ ] **Step 11: Commit**

```bash
git add CineBar/Sources/CineBar CineBar/Tests \
  CineBar/Info.plist CineBar/Assets/Localization
git commit -m "feat: switch CineBar to resilient custom endpoints"
```

---

### Task 5: Deploy and Verify the Custom Domains

**Files:**
- Modify only if deployment feedback requires a configuration correction already covered by Task 2.

**Interfaces:**
- Consumes: active `cinebar.cc` zone, Custom Domain configuration, existing secrets, and D1 binding.
- Produces: live `api.cinebar.cc`, `community.cinebar.cc`, `share.cinebar.cc`, and `cinebar.cc`.

- [ ] **Step 1: Confirm secrets and D1 without displaying values**

Run:

```bash
npx wrangler whoami
(cd CineBarDataProxy && npx wrangler secret list)
(cd CineBarCommunity && npx wrangler d1 list)
```

Verify the data Worker has `TMDB_TOKEN` and `OMDB_API_KEY` names, and the community config references database ID `2b469154-42fc-43cf-b47e-4f2f23ca9bba`. Never print secret values.

- [ ] **Step 2: Deploy all three Workers**

```bash
(cd CineBarDataProxy && npx wrangler deploy)
(cd CineBarCommunity && npx wrangler deploy)
(cd CineBarShare && npx wrangler deploy)
```

Verify deployment output includes:

- `api.cinebar.cc`;
- `community.cinebar.cc`;
- `share.cinebar.cc`;
- `cinebar.cc`.

- [ ] **Step 3: Wait for certificates to become active**

In Cloudflare **Workers & Pages → Worker → Settings → Domains & Routes**, verify each custom hostname is active. Do not bypass a browser TLS warning while waiting; a pending certificate is not a successful deployment.

- [ ] **Step 4: Smoke-test health endpoints without a proxy**

Temporarily disable the development Mac's system proxy through its normal network settings, then run:

```bash
curl --fail --silent --show-error --max-time 15 https://api.cinebar.cc/health
curl --fail --silent --show-error --max-time 15 https://community.cinebar.cc/health
curl --fail --silent --show-error --max-time 15 https://share.cinebar.cc/health
```

Restore the user's original proxy setting immediately after the test. Each response must identify the expected service and version `0.8.2-test.2`.

- [ ] **Step 5: Smoke-test real behavior**

Without printing complete payloads or secrets, verify:

```bash
curl --fail --silent --show-error \
  'https://api.cinebar.cc/movie/603?language=zh-CN'
curl --fail --silent --show-error \
  'https://api.cinebar.cc/omdb?i=tt0133093'
curl --fail --silent --show-error \
  'https://share.cinebar.cc/m/603'
curl --fail --silent --show-error \
  'https://share.cinebar.cc/updates/latest.json'
```

Assert movie ID 603, a non-empty title, OMDb `Response: "True"`, at least one rating, a branded share page, and Build 16 update metadata. Verify `/omdb?i=invalid` returns HTTP 400.

- [ ] **Step 6: Verify community read and one controlled submission**

Use a dedicated test media ID outside real TMDB IDs and a new test-only device identifier. Verify initial read, one accepted rating, and duplicate rejection. Do not delete or modify real user ratings.

- [ ] **Step 7: Verify certificate hostnames**

For all four hosts, inspect the peer certificate and verify hostname matching through a standard HTTPS client. No `--insecure`, trust override, custom CA, or certificate pin bypass is permitted.

- [ ] **Step 8: Commit any configuration-only correction**

If no correction was necessary, do not create an empty commit. If a route configuration correction was required:

```bash
git add CineBarDataProxy/wrangler.jsonc \
  CineBarCommunity/wrangler.toml \
  CineBarCommunity/wrangler.toml.example \
  CineBarShare/wrangler.jsonc
git commit -m "fix: correct CineBar custom domain routes"
```

---

### Task 6: Version, Document, Package, and Carrier-Test the Candidate

**Files:**
- Modify: `CineBar/Info.plist`
- Modify: `CineBar/Tools/build_test_package.sh`
- Modify: `CineBar/README.md`
- Modify: `CineBar/请先阅读-测试版安装说明.html`
- Modify: `CineBar/请先阅读-测试版安装说明.txt`
- Modify: `CineBarShare/worker.js`
- Create: `dist/CineBar-0.8.2-test.2-universal.zip`

**Interfaces:**
- Consumes: verified custom domains and completed client network integration.
- Produces: locally delivered Build 16 universal candidate and multi-carrier validation record.

- [ ] **Step 1: Update exact version metadata**

Set:

- `CFBundleShortVersionString` to `0.8.2`;
- `CFBundleVersion` to `16`;
- package name to `CineBar-0.8.2-test.2`;
- update manifest version to `0.8.2`, build to `16`, and notes to:

```javascript
[
  "中国区服务改用 CineBar 自定义域名",
  "增加网络错误重试与未来备用入口支持",
  "网络异常时优先显示上次成功加载的数据",
  "增加不含隐私信息的服务诊断",
]
```

- [ ] **Step 2: Update user documentation**

State clearly:

- no API key, Cloudflare, D1, proxy, or VPN is required;
- the three client service hosts use `cinebar.cc`;
- stale real data may be shown during a temporary outage;
- first-open Gatekeeper confirmation remains because the build is not notarized;
- no Hong Kong backup server is active yet;
- the four deferred feature requests are not part of test.2;
- the package is local and is not uploaded to GitHub.

- [ ] **Step 3: Run the complete local suite**

```bash
node --test CineBarDataProxy/tests/data-proxy.test.mjs
node --test CineBarCommunity/tests/community-rating.test.mjs
node --test CineBarShare/tests/share-worker.test.mjs
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-domain-final
/tmp/cinebar-domain-final
xcrun swiftc -parse-as-library -typecheck CineBar/Sources/CineBar/*.swift
plutil -lint CineBar/Info.plist
for file in CineBar/Assets/Localization/*.lproj/Localizable.strings; do
  plutil -lint "$file"
done
```

Expected: all tests pass, Swift commands exit 0, and every plist/strings file reports `OK`.

- [ ] **Step 4: Build the universal package**

```bash
bash CineBar/Tools/build_test_package.sh
```

Expected:

`dist/CineBar-0.8.2-test.2-universal.zip`

- [ ] **Step 5: Verify architecture, signature, metadata, guides, and secrets**

```bash
verification_dir=$(mktemp -d \
  "${TMPDIR:-/tmp}/cinebar-domain-release.XXXXXX")
ditto -x -k dist/CineBar-0.8.2-test.2-universal.zip "$verification_dir"
packaged_app=$(find "$verification_dir" -type d -name CineBar.app \
  -print -quit)
test -n "$packaged_app"
architectures=$(lipo -archs "$packaged_app/Contents/MacOS/CineBar")
case " $architectures " in *" arm64 "*) ;; *) exit 1;; esac
case " $architectures " in *" x86_64 "*) ;; *) exit 1;; esac
codesign --verify --deep --strict "$packaged_app"
test "$(plutil -extract CFBundleVersion raw \
  "$packaged_app/Contents/Info.plist")" = "16"
test "$(plutil -extract CineBarDataProxyURL raw \
  "$packaged_app/Contents/Info.plist")" = "https://api.cinebar.cc"
test "$(plutil -extract CineBarCommunityURL raw \
  "$packaged_app/Contents/Info.plist")" = "https://community.cinebar.cc"
test "$(plutil -extract CineBarShareURL raw \
  "$packaged_app/Contents/Info.plist")" = "https://share.cinebar.cc"
find "$verification_dir" -name '请先阅读-测试版安装说明.html' \
  -print -quit | grep -q .
find "$verification_dir" -name '请先阅读-测试版安装说明.txt' \
  -print -quit | grep -q .
! rg -a -n 'workers\\.dev' "$packaged_app"
shasum -a 256 dist/CineBar-0.8.2-test.2-universal.zip
```

Also compare the locally saved TMDB and OMDb values against the extracted package with fixed-string binary scanning, without printing either value.

- [ ] **Step 6: Perform China Mobile, Unicom, and Telecom tests**

For each carrier, with proxy and VPN disabled:

1. launch CineBar cold;
2. open Movies, Television, and My Watchlist;
3. open one movie and one television detail page;
4. load OMDb multi-ratings;
5. read a community score;
6. open one share page;
7. refresh the movie detail page;
8. repeat the three `/health` requests 30 times.

Record carrier, city, macOS version, test time, success count, DNS errors, TLS errors, timeouts, and screenshots of any failure. Do not record user names, IP addresses, device IDs, API keys, or rating payloads.

- [ ] **Step 7: Apply the release gate**

The build may be called a China-region test candidate only if every carrier completes all functional steps and all 30 health requests without DNS or TLS failures.

If any carrier reproduces a stable DNS/TLS failure:

- do not distribute test.2 as the fixed China build;
- keep `cinebar.cc`;
- start a separate design for a real `api-hk.cinebar.cc` backend;
- do not mask the failure with a certificate or ATS exception.

- [ ] **Step 8: Copy the accepted artifact to the delivery folder**

After the release gate passes:

```bash
mkdir -p /Users/bruce/Documents/Codex/2026-07-25/you/work/CineBar/build082
cp dist/CineBar-0.8.2-test.2-universal.zip \
  /Users/bruce/Documents/Codex/2026-07-25/you/work/CineBar/build082/
```

- [ ] **Step 9: Commit locally**

```bash
git diff --check
git add CineBar CineBarShare/worker.js \
  dist/CineBar-0.8.2-test.2-universal.zip
git commit -m "build: package CineBar custom-domain test release"
```

Do not push and do not create a GitHub Release.
