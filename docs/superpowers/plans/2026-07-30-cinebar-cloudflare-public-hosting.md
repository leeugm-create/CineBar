# CineBar Cloudflare Public Hosting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the reviewed CineBar website through a dedicated Cloudflare Worker and move only `cinebar.cc` to it while preserving every existing service subdomain.

**Architecture:** Build the existing vinext website into `dist/server` and `dist/client`, deploy those outputs as a new `cinebar-website` Worker, and validate its `workers.dev` production URL before changing any custom domain. After staging passes, remove only the apex custom domain from `cinebar-share-test`, attach it to `cinebar-website`, and run public regression checks with a documented rollback.

**Tech Stack:** vinext, Vite, React, Cloudflare Workers static assets, Wrangler 4, Node test runner, Cloudflare Custom Domains.

## Global Constraints

- The public website hostname is exactly `cinebar.cc`.
- The new Worker name is exactly `cinebar-website`.
- The website entrypoint is exactly `dist/server/index.js`.
- Website static assets come from exactly `dist/client`.
- The primary download URL remains exactly `https://github.com/leeugm-create/CineBar/releases`.
- `share.cinebar.cc` remains on `cinebar-share-test`.
- `api.cinebar.cc` and `community.cinebar.cc` remain unchanged.
- Build 16 application code and packages must not be rebuilt or modified.
- No Cloudflare OAuth token, API token, temporary credential, Sparkle private key, or Sites bypass token may be committed or printed in reports.
- The existing Sites project is retained but its owner-only URL is not published as the official website.
- Do not attach `cinebar.cc` until the `workers.dev` URL passes homepage, health, social-image, and metadata verification.
- If the apex cutover fails any critical check, restore `cinebar.cc` to `cinebar-share-test`.

---

## File Structure

- `CineBarWebsite/wrangler.public.jsonc`: durable Cloudflare Worker build-output and route configuration.
- `CineBarWebsite/tests/cloudflare-config.test.mjs`: source-level deployment invariants and domain-boundary tests.
- `CineBarWebsite/package.json`: reproducible `deploy:dry-run` and `deploy:public` commands.
- `CineBarShare/wrangler.jsonc`: remove only the `cinebar.cc` custom domain during cutover.
- `CineBarShare/tests/share-worker.test.mjs`: regression assertion for retained `share.cinebar.cc` ownership.
- `.superpowers/sdd/2026-07-30-cinebar-cloudflare-public-hosting/`: task briefs, reports, review diffs, and progress ledger.

### Task 1: Add a Reproducible Public Worker Configuration

**Files:**
- Create: `CineBarWebsite/wrangler.public.jsonc`
- Create: `CineBarWebsite/tests/cloudflare-config.test.mjs`
- Modify: `CineBarWebsite/package.json`

**Interfaces:**
- Consumes: the reviewed `npm run build` outputs at `dist/server/index.js` and `dist/client`.
- Produces: `npm run deploy:dry-run` and `npm run deploy:public`, both using `wrangler.public.jsonc`.

- [ ] **Step 1: Write the failing configuration contract**

Create `CineBarWebsite/tests/cloudflare-config.test.mjs`:

```js
import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) =>
  readFile(new URL(`../${path}`, import.meta.url), "utf8");

const parseJsonc = (source) =>
  JSON.parse(
    source
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, ""),
  );

test("deploys the reviewed vinext outputs as an isolated Worker", async () => {
  const config = parseJsonc(await read("wrangler.public.jsonc"));
  assert.equal(config.name, "cinebar-website");
  assert.equal(config.main, "dist/server/index.js");
  assert.deepEqual(config.compatibility_flags, ["nodejs_compat"]);
  assert.equal(config.no_bundle, true);
  assert.equal(config.workers_dev, true);
  assert.equal(config.assets.directory, "dist/client");
  assert.equal(config.observability.enabled, true);
  assert.equal(config.routes, undefined);
});

test("package scripts build before dry-run or deployment", async () => {
  const packageJson = JSON.parse(await read("package.json"));
  assert.equal(
    packageJson.scripts["deploy:dry-run"],
    "npm run build && wrangler deploy --config wrangler.public.jsonc --dry-run --outdir .wrangler/public-dry-run",
  );
  assert.equal(
    packageJson.scripts["deploy:public"],
    "npm run build && wrangler deploy --config wrangler.public.jsonc",
  );
});
```

- [ ] **Step 2: Run the test and confirm RED**

Run:

```bash
cd CineBarWebsite
node --test tests/cloudflare-config.test.mjs
```

Expected: FAIL because `wrangler.public.jsonc` and the scripts do not exist.

- [ ] **Step 3: Add the staging-safe Worker configuration**

Create `CineBarWebsite/wrangler.public.jsonc`:

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "cinebar-website",
  "main": "dist/server/index.js",
  "compatibility_date": "2026-05-15",
  "compatibility_flags": ["nodejs_compat"],
  "workers_dev": true,
  "preview_urls": true,
  "no_bundle": true,
  "rules": [
    {
      "type": "ESModule",
      "globs": ["**/*.js", "**/*.mjs"]
    }
  ],
  "assets": {
    "directory": "dist/client"
  },
  "observability": {
    "enabled": true
  }
}
```

Do not add `routes` in this task.

- [ ] **Step 4: Add reproducible package scripts**

Add these exact keys to `CineBarWebsite/package.json`:

```json
{
  "scripts": {
    "deploy:dry-run": "npm run build && wrangler deploy --config wrangler.public.jsonc --dry-run --outdir .wrangler/public-dry-run",
    "deploy:public": "npm run build && wrangler deploy --config wrangler.public.jsonc"
  }
}
```

Keep all existing scripts.

- [ ] **Step 5: Run GREEN tests and Wrangler dry-run**

Run:

```bash
node --test tests/cloudflare-config.test.mjs
npm test
npm run deploy:dry-run
```

Expected:

- both configuration tests pass;
- the existing website tests pass;
- Wrangler reports a valid Worker upload without changing external state;
- `.wrangler/public-dry-run` contains an upload manifest or Worker output.

- [ ] **Step 6: Commit**

```bash
git add CineBarWebsite/wrangler.public.jsonc \
  CineBarWebsite/tests/cloudflare-config.test.mjs \
  CineBarWebsite/package.json CineBarWebsite/package-lock.json
git commit -m "build: prepare CineBar website Worker deployment"
```

### Task 2: Deploy and Verify the Worker Without the Apex Domain

**Files:**
- No source modification expected.
- Create report only: `.superpowers/sdd/2026-07-30-cinebar-cloudflare-public-hosting/task-2-report.md`

**Interfaces:**
- Consumes: `npm run deploy:public` from Task 1 and the active Wrangler OAuth login.
- Produces: a publicly reachable `https://cinebar-website.<account-subdomain>.workers.dev` URL.

- [ ] **Step 1: Confirm identity and clean source**

Run:

```bash
git status --short
cd CineBarWebsite
npx wrangler whoami
```

Expected: Git output is empty and Wrangler identifies the previously authorized account. Do not copy credential paths or tokens into the report.

- [ ] **Step 2: Deploy the staging-safe Worker**

Run:

```bash
npm run deploy:public
```

Expected: Wrangler deploys `cinebar-website` and returns its exact `workers.dev` production URL. It must not mention `cinebar.cc`.

- [ ] **Step 3: Verify the production staging URL**

Set `website_url` to the exact Wrangler URL and run:

```bash
curl -fsS "$website_url/" | grep -F "今晚看什么？"
curl -fsS -D /tmp/cinebar-worker-health.headers \
  "$website_url/health" | grep -F '"cinebar-website"'
grep -iF "cache-control: no-store" /tmp/cinebar-worker-health.headers
curl -fsS -o /tmp/cinebar-worker-og.png "$website_url/og.png"
sips -g pixelWidth -g pixelHeight /tmp/cinebar-worker-og.png
curl -fsS "$website_url/" | grep -E \
  'https://[^"]+\.workers\.dev/og\.png'
```

Expected:

- homepage and health return 200;
- health body names `cinebar-website`;
- health is uncached;
- social image is 1200 by 630;
- rendered social metadata contains an absolute HTTPS Worker URL.

- [ ] **Step 4: Verify existing public services before cutover**

Run:

```bash
curl -fsS https://share.cinebar.cc/health | grep -F '"cinebar-share"'
curl -fsS "https://share.cinebar.cc/m/603?title=CineBar%20Test" |
  grep -F "CineBar Test"
curl -fsS https://api.cinebar.cc/health | grep -F '"cinebar-data"'
curl -fsS https://community.cinebar.cc/health |
  grep -F '"cinebar-community"'
```

Expected: all four existing service checks pass without changing or redeploying
their implementation.

- [ ] **Step 5: Record the deployment without committing external identifiers**

Write the exact Worker name, deployment/version ID, URL, HTTP results, and UTC
time to the Task 2 report. Do not add the transient URL to product source or
user-facing website copy.

### Task 3: Transfer Only `cinebar.cc` and Verify Rollback

**Files:**
- Modify: `CineBarWebsite/wrangler.public.jsonc`
- Modify: `CineBarWebsite/tests/cloudflare-config.test.mjs`
- Modify: `CineBarShare/wrangler.jsonc`
- Modify: `CineBarShare/tests/share-worker.test.mjs`

**Interfaces:**
- Consumes: the verified `cinebar-website` Worker and existing `cinebar-share-test` Worker.
- Produces: `cinebar.cc` on the website Worker and `share.cinebar.cc` retained on the share Worker.

- [ ] **Step 1: Write failing domain-boundary tests**

In the first test in `CineBarWebsite/tests/cloudflare-config.test.mjs`, remove
only this staging assertion:

```js
assert.equal(config.routes, undefined);
```

Append to `CineBarWebsite/tests/cloudflare-config.test.mjs`:

```js
test("owns only the CineBar apex custom domain after cutover", async () => {
  const config = parseJsonc(await read("wrangler.public.jsonc"));
  assert.deepEqual(config.routes, [
    { pattern: "cinebar.cc", custom_domain: true },
  ]);
});
```

Append to `CineBarShare/tests/share-worker.test.mjs` using its existing parser:

```js
test("keeps only the public share hostname", () => {
  const patterns = config.routes.map((route) => route.pattern);
  assert.deepEqual(patterns, ["share.cinebar.cc"]);
  assert.equal(config.routes[0].custom_domain, true);
});
```

Adapt only the local variable names to the existing test file; keep the exact
assertions and expected patterns.

- [ ] **Step 2: Run tests and confirm RED**

Run:

```bash
cd CineBarWebsite
node --test tests/cloudflare-config.test.mjs
cd ../CineBarShare
node --test tests/share-worker.test.mjs
```

Expected: website test fails because it has no route; share test fails because it still owns both hostnames.

- [ ] **Step 3: Commit the complete route-source change before deployment**

Add to `CineBarWebsite/wrangler.public.jsonc`:

```jsonc
"routes": [
  {
    "pattern": "cinebar.cc",
    "custom_domain": true
  }
]
```

Change `CineBarShare/wrangler.jsonc` routes to:

```jsonc
"routes": [
  {
    "pattern": "share.cinebar.cc",
    "custom_domain": true
  }
]
```

Run both test suites and commit:

```bash
git add CineBarWebsite/wrangler.public.jsonc \
  CineBarWebsite/tests/cloudflare-config.test.mjs \
  CineBarShare/wrangler.jsonc \
  CineBarShare/tests/share-worker.test.mjs
git commit -m "deploy: move CineBar apex to website Worker"
```

- [ ] **Step 4: Release the apex from the share Worker**

Run:

```bash
cd CineBarShare
npx wrangler deploy --config wrangler.jsonc
```

Expected: `share.cinebar.cc` remains attached and `cinebar.cc` is no longer listed for `cinebar-share-test`.

Immediately run:

```bash
curl -fsS https://share.cinebar.cc/health | grep -F '"cinebar-share"'
```

If this fails, stop and redeploy the previous `CineBarShare/wrangler.jsonc`
from the parent commit before doing anything to the website Worker.

- [ ] **Step 5: Attach the apex to the website Worker**

Run:

```bash
cd ../CineBarWebsite
npm run deploy:public
```

Expected: Wrangler lists both the Worker URL and the `cinebar.cc` custom domain.

- [ ] **Step 6: Verify the public cutover**

Run:

```bash
curl -fsS https://cinebar.cc/ | grep -F "今晚看什么？"
curl -fsS -D /tmp/cinebar-apex-health.headers \
  https://cinebar.cc/health | grep -F '"cinebar-website"'
grep -iF "cache-control: no-store" /tmp/cinebar-apex-health.headers
curl -fsS https://cinebar.cc/ | grep -F \
  'https://cinebar.cc/og.png'
curl -fsS https://share.cinebar.cc/health | grep -F '"cinebar-share"'
curl -fsS "https://share.cinebar.cc/m/603?title=CineBar%20Test" |
  grep -F "CineBar Test"
```

Expected: every command passes over HTTPS with no certificate warning.

- [ ] **Step 7: Execute rollback if any critical check fails**

If Step 6 fails:

1. Restore `CineBarShare/wrangler.jsonc` from the parent of the route commit so it
   contains both custom domains.
2. Deploy `cinebar-share-test`.
3. Remove `routes` from the website Worker config and redeploy
   `cinebar-website`.
4. Verify `share.cinebar.cc/health` and record the failed check.
5. Revert the route-source commit without using `git reset --hard`.

Do not claim the website is public until Step 6 passes after a fresh request.

- [ ] **Step 8: Record final evidence**

Update the Task 3 report with:

- website Worker deployment/version ID;
- UTC cutover time;
- HTTP status for homepage, health, social image, and share health;
- TLS success;
- whether rollback was needed;
- confirmation that `api.cinebar.cc`, `community.cinebar.cc`, and Build 16 files were unchanged.
