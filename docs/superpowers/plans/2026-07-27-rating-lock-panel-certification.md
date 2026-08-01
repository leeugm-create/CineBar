# CineBar Rating Lock, Panel Placement, and Certification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a test-only CineBar build that enforces one anonymous rating per device and title, fixes slider/window drag conflicts and multi-display placement, makes content certification prominent, deploys the share service, and includes detailed installation instructions.

**Architecture:** The Cloudflare Worker remains the authority for immutable ratings and returns HTTP 409 for duplicates. The macOS client reflects server state, uses a native AppKit slider that does not move the panel, and calculates panel placement from the actual status-item button screen. Community, sharing, and data-proxy Workers remain separate services.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Foundation, Cloudflare Workers, D1, Node.js built-in test runner, Wrangler, Git test branch.

## Global Constraints

- Do not add user accounts, registration, or login.
- One anonymous installation may rate one movie or television title once.
- Scores remain 0–10 in 0.5 increments.
- Submitted scores cannot be edited or deleted.
- This work ships only on `test/rating-lock-multiscreen`; do not modify `main` or create a formal GitHub Release.
- Do not commit Cloudflare secrets, real `wrangler.toml`, caches, historical builds, or signing credentials.
- The test package must contain detailed Chinese installation instructions for non-technical users.

---

### Task 1: Make Community Ratings Immutable

**Files:**
- Modify: `CineBarCommunity/tests/community-rating.test.mjs`
- Modify: `CineBarCommunity/worker.js`
- Modify: `CineBarCommunity/README.md`

**Interfaces:**
- Consumes: `POST /v1/:mediaType/:mediaID/rating`, anonymous device header, D1 `ratings` primary key.
- Produces: first POST returns a summary, repeated POST returns HTTP 409 with `already_rated`, DELETE returns HTTP 405.

- [ ] **Step 1: Write failing route tests**

Add a stateful in-memory D1 adapter and send real `Request` objects through `worker.fetch`. Assert that a first score of `8.0` succeeds, a second score of `3.0` returns `409`, the stored score remains `8.0`, and DELETE returns `405`.

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
node --test CineBarCommunity/tests/community-rating.test.mjs
```

Expected: the duplicate POST and DELETE tests fail because the current Worker updates and deletes ratings.

- [ ] **Step 3: Implement insert-only writes**

Replace `upsertRating` with `createRating`. Query the existing device/title row before insert, return:

```json
{"error":"这部影片已经评分，不能重复评分","code":"already_rated"}
```

with status 409, use a plain `INSERT`, map D1 unique-constraint races to the same 409 response, and return 405 for DELETE.

- [ ] **Step 4: Run the tests and verify GREEN**

Run the Node test command again. Expected: all route and normalization tests pass.

- [ ] **Step 5: Document the immutable API**

Update the service README to explain one score per anonymous installation, HTTP 409 duplicates, and the absence of edit/delete APIs.

- [ ] **Step 6: Commit**

```bash
git add CineBarCommunity
git commit -m "fix: enforce one-time community ratings"
```

### Task 2: Reflect One-Time Rating State in the macOS Client

**Files:**
- Create: `CineBar/Tests/RegressionBehaviorTests.swift`
- Modify: `CineBar/Sources/CineBar/main.swift`

**Interfaces:**
- Consumes: `CommunityRatingSummary.myScore`, Worker HTTP 409 response.
- Produces: `CommunityRatingError.alreadyRated`, `RatingPresentation.shouldShowEditor(myScore:isLoading:)`, and a separate “我的评分” item appended after the CineBar average.

- [ ] **Step 1: Add failing client behavior tests**

Compile the production source with `-D CINEBAR_TEST` and test that:

```swift
precondition(RatingPresentation.shouldShowEditor(myScore: nil, isLoading: false))
precondition(!RatingPresentation.shouldShowEditor(myScore: 8.5, isLoading: false))
precondition(!RatingPresentation.shouldShowEditor(myScore: nil, isLoading: true))
```

Also assert that the rating list ends with a “我的评分” entry when `myScore` exists.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-regression-tests
/tmp/cinebar-regression-tests
```

Expected: compilation fails because the presentation helper and test build guard do not exist.

- [ ] **Step 3: Add client conflict handling and presentation state**

Guard the app `@main` entry with `#if !CINEBAR_TEST`, add `CommunityRatingError.alreadyRated`, map HTTP 409 to it, remove the client DELETE method, and reload the summary after a duplicate conflict. Append the user's immutable score after the aggregate CineBar rating for both movie and TV details.

- [ ] **Step 4: Run the Swift regression test and verify GREEN**

Run the same compile and executable commands. Expected: all preconditions pass with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add CineBar/Sources/CineBar/main.swift CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "fix: hide immutable rating editor after submission"
```

### Task 3: Replace the Rating Slider and Add Submission Confirmation

**Files:**
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Assets/Localization/en.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ja.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ko.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/zh-Hant.lproj/Localizable.strings`

**Interfaces:**
- Produces: `RatingNSSlider`, `RatingSlider`, and localized one-time submission confirmation copy.

- [ ] **Step 1: Add a failing native-control regression test**

Instantiate the slider on the main actor and assert:

```swift
precondition(slider.minValue == 0)
precondition(slider.maxValue == 10)
precondition(slider.numberOfTickMarks == 21)
precondition(slider.allowsTickMarkValuesOnly)
precondition(!slider.mouseDownCanMoveWindow)
```

- [ ] **Step 2: Run the Swift test and verify RED**

Expected: compilation fails because `RatingNSSlider` does not exist.

- [ ] **Step 3: Implement the AppKit slider and confirmation**

Wrap `NSSlider` with `NSViewRepresentable`, use a 0–10 range with 21 tick marks, make it continuous, increase its intrinsic height, and override `mouseDownCanMoveWindow` to `false`. Display the warning:

> 每部影片只能评分一次，提交后不可修改或删除，请谨慎评分。

Show a confirmation dialog before calling `saveCommunityRating`. Remove the delete button. Hide the entire editor when a score exists.

- [ ] **Step 4: Add translations**

Add complete English, Japanese, Korean, and Traditional Chinese translations for the warning, confirmation title, submit action, cancel action, saved message, and duplicate message.

- [ ] **Step 5: Run Swift tests and type-check**

```bash
/tmp/cinebar-regression-tests
xcrun swiftc -parse-as-library -typecheck CineBar/Sources/CineBar/main.swift
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit**

```bash
git add CineBar
git commit -m "fix: make one-time rating control easy to drag"
```

### Task 4: Fix Status-Item Screen Placement and Enlarge Certification

**Files:**
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`
- Modify: `CineBar/Sources/CineBar/main.swift`

**Interfaces:**
- Produces: `PanelPlacement.frame(anchorX:currentFrame:visibleFrame:minHeight:)` and a redesigned `ContentRatingBadge`.

- [ ] **Step 1: Add failing placement tests**

Use hand-calculated screen fixtures to assert that:

- a 520-point panel anchored on the second display stays inside that display;
- a panel restored from a large screen is clamped to a smaller display;
- the anchor is horizontally centered when space permits.

- [ ] **Step 2: Run the Swift test and verify RED**

Expected: compilation fails because `PanelPlacement` does not exist.

- [ ] **Step 3: Implement status-button placement**

Calculate the anchor from `statusItem.button.window.screen` and the button's converted screen frame. Always reposition when opening, including when panel movement is enabled. Fall back to the mouse screen and then `NSScreen.main` only when the status button has no screen.

- [ ] **Step 4: Redesign certification hierarchy**

Render the region in small secondary text, the original certification in large red bold type, and CineBar's normalized age as subordinate explanatory text. Use the same component for movies and TV.

- [ ] **Step 5: Run regression tests and type-check**

Expected: placement tests and Swift type-check pass.

- [ ] **Step 6: Commit**

```bash
git add CineBar
git commit -m "fix: anchor panel to the clicked menu bar screen"
```

### Task 5: Prepare the Detailed Test Installation Guide

**Files:**
- Create: `CineBar/请先阅读-测试版安装说明.html`
- Create: `CineBar/请先阅读-测试版安装说明.txt`
- Modify: `CineBar/Info.plist`
- Modify: `CineBar/README.md`

**Interfaces:**
- Produces: CineBar 0.8.1 build 13 test metadata and user-facing installation documentation.

- [ ] **Step 1: Write the installation guide**

Cover downloading and extracting, dragging `CineBar.app` to Applications, first launch with right-click → Open, Privacy & Security → Open Anyway, enabling notifications and login launch, locating the menu-bar icon, test-only limitations, quitting, uninstalling, and safe troubleshooting. Do not instruct users to disable Gatekeeper globally.

- [ ] **Step 2: Update test metadata**

Set `CFBundleShortVersionString` to `0.8.1`, `CFBundleVersion` to `13`, and identify the package as `0.8.1-test.1` in filenames and documentation.

- [ ] **Step 3: Validate documentation and plist**

```bash
plutil -lint CineBar/Info.plist
open CineBar/请先阅读-测试版安装说明.html
```

Visually confirm the HTML is readable and complete.

- [ ] **Step 4: Commit**

```bash
git add CineBar
git commit -m "docs: add detailed test installation guide"
```

### Task 6: Deploy Services and Build the Test Package

**Files:**
- Create: `CineBar/Tools/build_test_package.sh`
- Modify: `CineBarShare/README.md`
- Modify: `CineBar/Info.plist`
- Create at build time: `dist/CineBar-0.8.1-test.1-universal.zip`

**Interfaces:**
- Consumes: logged-in Wrangler session and existing D1 database binding.
- Produces: deployed immutable community API, test share Worker URL, universal ad-hoc-signed application package with installation documents.

- [ ] **Step 1: Create and validate the repeatable build script**

The script must compile arm64 and x86_64 with macOS 13 minimum, combine them with `lipo`, assemble resources and localizations, ad-hoc sign the app, create a delivery folder containing the app and both installation guides, and zip that folder into `dist`.

- [ ] **Step 2: Deploy the community Worker**

Create an ignored worktree-local `CineBarCommunity/wrangler.toml` with binding `DB`, database name `cinebar-community`, and database ID `2b469154-42fc-43cf-b47e-4f2f23ca9bba`. Run:

```bash
cd CineBarCommunity
npx wrangler deploy
```

Verify the existing service URL responds and repeated ratings return 409 without changing the score.

- [ ] **Step 3: Deploy the independent test share Worker**

Run:

```bash
cd CineBarShare
npx wrangler deploy --name cinebar-share-test
```

Write the returned test URL to `CineBarShareURL`, then verify `/`, a movie share URL, and `/updates/latest.json`.

- [ ] **Step 4: Build the universal test package**

Run:

```bash
bash CineBar/Tools/build_test_package.sh
```

Expected: `dist/CineBar-0.8.1-test.1-universal.zip`.

- [ ] **Step 5: Verify the artifact**

Check both architectures with `lipo -info`, validate the bundle plist, verify the code signature, list the ZIP contents, and confirm both installation documents are present.

- [ ] **Step 6: Commit**

```bash
git add CineBar CineBarShare dist/CineBar-0.8.1-test.1-universal.zip
git commit -m "build: package CineBar 0.8.1 test release"
```

### Task 7: Final Verification and GitHub Test-Branch Upload

**Files:**
- Verify all modified files.

**Interfaces:**
- Produces: pushed branch `origin/test/rating-lock-multiscreen`; no change to `origin/main`.

- [ ] **Step 1: Run the full verification suite**

```bash
node --test CineBarCommunity/tests/community-rating.test.mjs
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-regression-tests
/tmp/cinebar-regression-tests
xcrun swiftc -parse-as-library -typecheck CineBar/Sources/CineBar/main.swift
plutil -lint CineBar/Info.plist
```

- [ ] **Step 2: Review branch safety**

Confirm `git status --short` is clean, `git diff origin/main...HEAD` contains no secrets or caches, and the current branch is `test/rating-lock-multiscreen`.

- [ ] **Step 3: Push only the test branch**

```bash
git push -u origin test/rating-lock-multiscreen
```

- [ ] **Step 4: Verify GitHub**

Open the branch URL and confirm source, tests, documentation, and the test ZIP are present while `main` remains unchanged.
