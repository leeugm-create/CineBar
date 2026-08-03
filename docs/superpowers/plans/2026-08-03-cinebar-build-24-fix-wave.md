# CineBar Build 24 Fix Wave Implementation Plan

> **For agentic workers:** Execute inline in the shared worktree. Do not delegate this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve every Critical and Important local-library review finding and publish a traceable `0.8.3-test.8` Build 24 without overwriting Build 23.

**Architecture:** Keep filesystem indexing, persistence, metadata matching, and external playback separated. Store scan and error state as language-neutral data, merge scan output into the current main-actor snapshot, renew bookmarks in place, and return structured playback outcomes. Build only from a clean committed source tree and embed the exact commit and source status in the package.

**Tech Stack:** Swift 5, SwiftUI, AppKit, Foundation, EventKit, macOS security-scoped bookmarks, Node test runner, Sparkle 2.9.2, shell packaging, Next/vinext, Cloudflare Workers.

## Global Constraints

- Minimum macOS version remains 13.0 and the app remains Universal `arm64` plus `x86_64`.
- `CFBundleShortVersionString` remains `0.8.3`; Build 24 is marketed as `0.8.3-test.8`.
- Build 23 URLs and artifacts are immutable and remain available as history.
- No local path, file content, or video is uploaded; no piracy, magnet, torrent, or third-party media-download aggregation is added.
- Existing user-intended tracked changes must be reviewed and committed before packaging.
- Release and deployment happen only after tests, clean-source checks, archive verification, and Sparkle signature verification pass.

---

### Task 1: Preserve and validate intended worktree changes

**Files:** `CineBar/Sources/CineBar/main.swift`, `CineBar/Tests/RegressionBehaviorTests.swift`, `CineBar/Info.plist`, `CineBar/Tools/build_test_package.sh`, `CineBarCommunity/worker.js`, `CineBarWebsite/app/layout.tsx`

- [ ] Inspect the complete tracked diff and exclude temporary archives, `.superpowers/brainstorm`, and reports from source commits.
- [ ] Run the existing Swift and Node regressions to identify failures attributable to these changes.
- [ ] Commit the intended feature changes only after the baseline test gate passes.

### Task 2: Repair refresh, authorization, and reattachment invariants

**Files:** `CineBar/Sources/CineBar/LocalLibrary.swift`, `LocalLibraryScanner.swift`, `LocalLibraryStore.swift`, `CineBar/Tests/RegressionBehaviorTests.swift`

- [ ] Add a failing regression where a watched/watchlist/metadata/opened mutation made during an active scan survives the final merge.
- [ ] Add failing regressions for stale bookmark renewal retaining the same folder ID and avoiding duplicate entries.
- [ ] Add failing signature regressions covering lightweight equality, resource-ID corroboration, cross-volume differing IDs, and mismatch non-mutation.
- [ ] Implement current-state merging, language-neutral store messages, in-place bookmark renewal, and corrected signature matching.
- [ ] Run the focused Swift regression after each red-green cycle.

### Task 3: Repair playback, matching presentation, and localization

**Files:** `LocalLibraryPlayback.swift`, `LocalLibraryMatchService.swift`, `LocalLibraryView.swift`, localization files, regression tests, Tools tests

- [ ] Add failing tests for a structured player outcome and ordered per-provider failures.
- [ ] Add failing tests that last-opened state changes only after a verified success.
- [ ] Add candidate metadata genre preservation and poster/year/type/genre/rating presentation coverage.
- [ ] Introduce AppLanguage-based localization lookup and render language-neutral store errors in the view.
- [ ] Show full authorized path, provider failure reasons, and a copy action when all players fail.
- [ ] Run Swift and localization tests after every red-green cycle.

### Task 4: Enforce build provenance

**Files:** `CineBar/Tools/build_test_package.sh`, Tools tests, package resources

- [ ] Add failing script tests proving dirty tracked source inputs are rejected.
- [ ] Add failing tests for an embedded manifest containing commit, version, build, and clean source status.
- [ ] Implement the clean-tree guard and manifest generation without depending on untracked temporary files.
- [ ] Commit all source, tests, docs, and build-script changes before invoking the build.

### Task 5: Prepare and publish Build 24

**Files:** version metadata, five localizations, README/install guides, Build 24 release notes, website, Share worker/tests, appcast, Build 24 archives, final report

- [ ] Bump Build to 24 and update all public copy to `0.8.3-test.8`, explicitly stating signed in-app update availability.
- [ ] Run the complete Swift, Tools, Share, website, and diff checks from a clean tracked tree.
- [ ] Build the Universal package, verify manifest commit/status, Info.plist, localizations, release notes, architectures, and code signature.
- [ ] Generate the new immutable Build 24 archive URL and a real Sparkle signature/length; retain Build 23 history in the appcast.
- [ ] Commit release metadata and artifacts, deploy website and Share, then verify appcast, archive SHA-256, latest manifest, and health endpoints.
- [ ] Update the final task report with exact commands, hashes, signatures, deployment identifiers, and any manual acceptance limitations.

## Self-review checklist

- Every Critical/Important review finding maps to Tasks 2–5.
- Dirty-source provenance is prevented by behavior, not merely documented.
- Store errors are not localized until the view has the selected AppLanguage.
- Build 23 is never overwritten.
- No placeholder, deferred fix, fabricated signature, or unverified completion claim is allowed.
