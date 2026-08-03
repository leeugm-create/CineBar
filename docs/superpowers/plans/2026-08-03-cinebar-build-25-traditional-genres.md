# CineBar Build 25 Traditional Genre Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct Traditional Chinese Local Library genre names and publish a provenance-verified `0.8.3-test.9` Build 25 without altering prior immutable releases.

**Architecture:** Expand the existing genre-localization value table so Simplified and Traditional Chinese have separate literal outputs, then exercise the real mapping from the Swift regression executable. Prepare Build 25 metadata in a separate clean commit, build through the existing provenance gate, prepend a signed appcast item, and validate local and remote artifacts byte-for-byte.

**Tech Stack:** Swift/AppKit/SwiftUI, Node test runner, shell release tooling, Sparkle 2.9.2, Cloudflare Wrangler.

## Global Constraints

- Keep `CFBundleShortVersionString` at `0.8.3`; set `CFBundleVersion` to `25`.
- Publish test label `0.8.3-test.9` and immutable Build 25 URL.
- Preserve Build 24 and Build 23 ZIPs and appcast entries unchanged.
- Do not add piracy, torrent, or media-download aggregation.
- Build only from committed clean release inputs and embed the manifest.

---

### Task 1: Correct Traditional Chinese genres

**Files:**
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`
- Modify: `CineBar/Sources/CineBar/LocalLibraryView.swift`

**Interfaces:**
- Consumes: `LocalLibraryGenreLocalization.title(id:language:)`
- Produces: distinct Simplified, Traditional, English, Japanese, and Korean genre output

- [ ] Add literal regression assertions for multiple genre IDs in all supported languages, including `冒險`, `科幻與奇幻`, and `電視電影` for Traditional Chinese.
- [ ] Run the Swift regression executable and confirm failure on the current shared Chinese table.
- [ ] Add distinct Traditional Chinese values and route `.zhHK`/`.zhTW` to them.
- [ ] Run Swift regression and Tools tests; confirm green.
- [ ] Commit only source, test, and this plan.

### Task 2: Prepare clean Build 25 inputs

**Files:**
- Modify: `CineBar/Info.plist`
- Create: `CineBar/ReleaseNotes/0.8.3-test.9-Build-25.txt`
- Modify: `CineBar/README.md`
- Modify: `CineBar/INSTALL.md`
- Modify: `CineBar/请先阅读-测试版安装说明.html`
- Modify: `CineBar/请先阅读-测试版安装说明.txt`
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBarWebsite/app/page.tsx`
- Modify: `CineBarWebsite/tests/content.test.mjs`
- Modify: `CineBarShare/worker.js`
- Modify: `CineBarShare/wrangler.jsonc`
- Modify: `CineBarShare/tests/share-worker.test.mjs`
- Modify: `CineBar/Tools/tests/app-branding.test.mjs`

**Interfaces:**
- Produces: consistent Build 25 app, website, update JSON, health, documentation, and immutable download metadata

- [ ] Update metadata tests to expect `0.8.3-test.9`, Build 25, and the Build 25 immutable URL; confirm red.
- [ ] Update production metadata and concise release notes while retaining Build 24 history.
- [ ] Run Swift, Tools, Share, Community, and Website gates.
- [ ] Commit all release inputs, then verify the build-input status is clean.

### Task 3: Build, sign, deploy, and verify Build 25

**Files/Artifacts:**
- Create: `dist/CineBar-0.8.3-test-build-25-universal.zip`
- Create: `CineBarWebsite/public/downloads/CineBar-0.8.3-test-build-25-universal.zip`
- Modify: `CineBarWebsite/public/appcast.xml`
- Update outside release commit: `task-7-report.md`

**Interfaces:**
- Produces: signed Build 25 appcast item followed by unchanged Build 24 and Build 23 items

- [ ] Build with `CineBar/Tools/build_test_package.sh` and verify manifest commit/tree, Build 25 plist, Universal architectures, and deep code signature.
- [ ] Sign Build 25 with Sparkle, verify signature and enclosure length, copy to the new immutable URL, and confirm Build 24 SHA is unchanged.
- [ ] Commit only Build 25 artifact copies and appcast.
- [ ] Deploy Website and Share worker.
- [ ] Download Build 25 remotely and verify SHA, Sparkle signature, appcast order `25,24,23`, latest JSON, health, and homepage copy.
- [ ] Update the final task report with Build 25 evidence and run the complete gate again before reporting readiness.
