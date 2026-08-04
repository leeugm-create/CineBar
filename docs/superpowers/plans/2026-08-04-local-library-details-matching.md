# Local Library Detail Bridge and Matching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将本地片库完善为“电影 / 电视剧 / 其他视频”三个可见栏目；已确认的电影和电视剧进入现有完整详情页，其他视频保留为本地文件详情；匹配窗口支持关闭、模糊搜索和最佳建议，并保持本地片库状态安全可回退。

**Architecture:** `LocalLibraryView` 负责栏目与状态筛选、列表和路由入口；`LocalLibraryDetailBridge` 将确认后的本地元数据转换成既有 `Movie`/`TVShow` 模型，由 `MovieStore` 复用现有详情加载链路；`LocalLibraryFileDetailView` 只展示本地文件信息；`LocalLibraryMatchService` 负责可解释的标题/年份模糊排序，匹配结果必须由用户确认后才写入本地条目。

**Tech Stack:** Swift 5 / SwiftUI / EventKit（既有详情能力）、Swift 编译回归测试（`xcrun swiftc`）、Node.js `node:test` 静态资源测试、Sparkle 测试包脚本。

## Global Constraints

- 不把未确认的本地文件伪装成电影或电视剧；自拍、相机片段和其他视频只能进入“其他视频”，除非用户主动搜索并确认匹配。
- 不新增账号登录，不接入盗版资源，不改变既有 TMDB、OMDb、TVMaze、社区评分和 CineBar 自评分数据链路。
- 电影/电视剧详情必须复用现有 `MovieDetailView` / `TVDetailView`，不得复制一套详情页；因此现有演员、评分、剧照、预告和自评逻辑继续生效。
- 本地片库关闭按钮、匹配窗口关闭按钮必须可用；关闭或返回不能丢失当前栏目、筛选条件和已扫描数据。
- 所有新增用户可见文字同时补齐简体中文、繁体中文、英文、日文、韩文；缺失翻译不得依赖 key 作为最终 UI 文案。
- 任何“最佳建议”都只是排序提示，不得自动确认或覆盖既有手动匹配。

---

## Task 1: Add test-first metadata bridge and matching behavior

**Files:**
- Add `CineBar/Sources/CineBar/LocalLibraryDetailBridge.swift`.
- Modify `CineBar/Sources/CineBar/LocalLibraryMatchService.swift`.
- Modify `CineBar/Tests/RegressionBehaviorTests.swift`.

- [ ] Add regression preconditions before implementation for: a confirmed movie metadata value creates a `Movie` with the same ID/title/overview/year/poster; a confirmed TV value creates a `TVShow`; an absolute legacy poster URL is normalized without duplicating `/t/p/w342`; a typo query ranks the intended title above a merely containing title; and a manual `LocalLibraryMatchQuery(kind: .movie)` works even when its originating entry is `.other`.
- [ ] Run the existing Swift regression command and record the expected failure (the new bridge symbols/ranking assertions must fail before implementation).
- [ ] Implement `LocalLibraryDetailBridge.movie(from:)` and `.television(from:)`, including four-digit year validation, raw TMDB poster-path preservation, and legacy absolute-poster normalization.
- [ ] Extend `LocalLibraryMatchCandidate` to retain the source `posterPath` rather than persisting a generated absolute poster URL; keep `posterURL` as a derived presentation value.
- [ ] Keep automatic `search(for:)` empty for untrusted `.other` files, but ensure the explicit `search(query:)` path is never blocked by the entry category; retain deterministic confidence, year bonus, and vote-average tie-breaking.
- [ ] Re-run the Swift regression command and require all new and existing preconditions to pass.

**Verification:**
```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST CineBar/Sources/CineBar/*.swift CineBar/Tests/RegressionBehaviorTests.swift -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
```

## Task 2: Split local-library filtering into visible category tabs and status filtering

**Files:**
- Modify `CineBar/Sources/CineBar/LocalLibrary.swift`.
- Modify `CineBar/Sources/CineBar/LocalLibraryView.swift`.
- Modify `CineBar/Tests/RegressionBehaviorTests.swift`.

- [ ] Introduce internal, testable `LocalLibraryCategoryFilter` (`全部`, `电影`, `电视剧`, `其他视频`) and `LocalLibraryStatusFilter` (`全部`, `未观看`, `未匹配`, `不可用`) with pure `includes` methods; preserve current filename/title search and stable sort order.
- [ ] Add regression preconditions covering category-only filtering, category plus status filtering, and that an `.other` entry remains visible even when it has no external metadata.
- [ ] Replace the current local-library filter menu’s content-type choices with a visible segmented category picker, retaining a separate status menu so users can combine both dimensions.
- [ ] Keep the existing global Movies/TV/Watchlist/Local Library navigation intact, but make the local category picker the primary local-library subdivision; preserve close, refresh, add-folder, and empty/error states.
- [ ] Run Swift regression and source-level UI assertions after the filter refactor.

**Verification:**
```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST CineBar/Sources/CineBar/*.swift CineBar/Tests/RegressionBehaviorTests.swift -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
node --test CineBar/Tools/tests/*.test.mjs
```

## Task 3: Add detail routing and a local-file detail screen

**Files:**
- Modify `CineBar/Sources/CineBar/LocalLibraryView.swift`.
- Modify `CineBar/Sources/CineBar/main.swift`.
- Add or extend `CineBar/Tools/tests/app-branding.test.mjs` with static route/UI assertions if needed.

- [ ] Add an explicit “查看详情” action to movie/TV rows with confirmed metadata; convert metadata through `LocalLibraryDetailBridge` and call `MovieStore.select(_:)` / `selectTV(_:)` so the existing detail screens load all ratings, cast, stills, trailers, and self-rating.
- [ ] Keep `MovieStore.isShowingLocalLibrary` true while a local movie/TV detail is selected, then reorder `ContentView` route checks so selected movie/TV details take precedence over the local-library list and Back returns to the same local category/filter context.
- [ ] Add `LocalLibraryFileDetailView` for `.other` entries and unmatched entries. It must show filename, relative path, folder, file size, watched/watchlist state, and a “匹配影片或电视剧” action; it must not invent external scores or cast.
- [ ] Add a sheet route for the local-file detail, with a working top-left close button and dismiss behavior that leaves the local list intact.
- [ ] When a user confirms a candidate from any local entry, write the match through `LocalLibraryStore.confirmMatch`, close the matching UI, and open the bridged Movie/TV detail; never auto-confirm the first suggestion.
- [ ] Add source assertions for category tabs, detail action, `LocalLibraryFileDetailView`, bridge calls, and route precedence; run the Swift and Node suites.

**Verification:**
```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST CineBar/Sources/CineBar/*.swift CineBar/Tests/RegressionBehaviorTests.swift -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
node --test CineBar/Tools/tests/*.test.mjs
```

## Task 4: Improve matching UI with close, fuzzy search, and best-suggestion affordances

**Files:**
- Modify `CineBar/Sources/CineBar/LocalLibraryView.swift`.
- Modify `CineBar/Assets/Localization/zh-Hans.lproj/Localizable.strings`.
- Modify `CineBar/Assets/Localization/zh-Hant.lproj/Localizable.strings`.
- Modify `CineBar/Assets/Localization/en.lproj/Localizable.strings`.
- Modify `CineBar/Assets/Localization/ja.lproj/Localizable.strings`.
- Modify `CineBar/Assets/Localization/ko.lproj/Localizable.strings`.

- [ ] Add a top-left xmark button to `LocalLibraryMatchSheet`, wire it to the same dismissal path as Cancel/Skip, and ensure it works while a search request is in flight.
- [ ] Allow explicit search from `.other` entries with a title text field, movie/TV kind selector, clear button, and fuzzy results; keep the initial automatic suggestion list empty for untrusted filenames.
- [ ] Mark the first sorted candidate with a localized “最佳建议” badge and show a compact localized similarity percentage; explain that confirmation is manual and irreversible for the current entry.
- [ ] Keep async errors visible without erasing the last successful candidate list; make empty results distinguish “请输入片名” from “没有找到候选项”.
- [ ] Add translations for the new labels (`查看详情`, `文件详情`, `路径`, `文件大小`, `最佳建议`, `相似度`, `关闭匹配`, `匹配影片或电视剧`, and equivalent UI copy) in all five localization files.
- [ ] Run source tests and a grep-based check that no new user-visible key is missing from a locale.

**Verification:**
```bash
node --test CineBar/Tools/tests/*.test.mjs
for locale in zh-Hans zh-Hant en ja ko; do test -f "CineBar/Assets/Localization/$locale.lproj/Localizable.strings"; done
```

## Task 5: Update release metadata and package as the next in-app-updatable test build

**Files:**
- Modify `CineBar/Info.plist` (increment `CFBundleVersion` from 26 to 27; keep `CFBundleShortVersionString` at `0.8.3`).
- Modify `CineBar/Sources/CineBar/main.swift` in the Settings/About and New Features copy from Build 26 to Build 27.
- Modify `CineBar/README.md`, `CineBar/INSTALL.md`, `CineBar/请先阅读-测试版安装说明.html`, and `CineBar/请先阅读-测试版安装说明.txt` to identify `0.8.3-test.11` / Build 27 and the new local-library changes.
- Add `CineBar/ReleaseNotes/0.8.3-test.11-Build-27.txt` with concise change notes.
- Modify `CineBarWebsite/app/page.tsx` and any website download/version manifest that currently advertises Build 26, keeping the existing website style and download URL conventions.

- [ ] Update every user-facing and packaging reference consistently; do not change the Sparkle feed URL or public key.
- [ ] Run `CineBar/Tools/check_build_provenance.sh` through the package script’s tracked-input list before building, so the manifest includes the bridge/UI/localization/release changes.
- [ ] Build the universal signed test package with `CineBar/Tools/build_test_package.sh`; verify the ZIP contains `CineBar.app`, `ReleaseNotes`, both installation guides, and `BuildManifest.json`.
- [ ] Generate/update the signed appcast entry using the existing `CineBar/Tools/publish_sparkle_update.sh` workflow only after the package and release notes are reviewed; never publish a package whose signature cannot be verified.

**Verification:**
```bash
node --test CineBar/Tools/tests/*.test.mjs
CineBar/Tools/build_test_package.sh
unzip -l dist/CineBar-0.8.3-test-build-27-universal.zip
CineBar/Tools/check_build_provenance.sh "$(pwd)" 0.8.3 27 CineBar/Sources/CineBar CineBar/Info.plist CineBar/PkgInfo CineBar/Assets CineBar/ReleaseNotes CineBar/INSTALL.md CineBar/README.md CineBar/请先阅读-测试版安装说明.html CineBar/请先阅读-测试版安装说明.txt CineBar/Tools/build_test_package.sh CineBar/Tools/check_build_provenance.sh
```

## Task 6: Final regression, artifact audit, and handoff

**Files:** no additional source files; inspect the generated artifact and tracked diff.

- [ ] Run the complete Swift regression command, all Node tests, and website lint/build checks from the current repository scripts.
- [ ] Inspect `git diff --check`, the generated build manifest, app bundle signature, Sparkle feed version/build, and the final ZIP path.
- [ ] Confirm the manual test flow: Local Library → Other videos → close detail → match typo → see Best Suggestion → confirm → Movie/TV detail → Back preserves category; also verify Movie/TV category tabs and status filtering.
- [ ] Report exact package path, version/build, test commands and results, and the token usage for this modification; do not claim in-app update availability unless the signed appcast entry was actually published and verified.
