# Task 3 Report: Local Library Detail Routing

## Status

Complete. Confirmed local movies and television entries now bridge into the existing `MovieDetailView` / `TVDetailView` loading paths, while unmatched and `.other` entries open a local-file-only detail sheet. Back and dismiss paths retain the Local Library search, category, and status-filter context.

## Implementation commit

`6acd5ed73fc08e4c3f1d0047fe3b8015a40e8b80` (`feat: route local library details`)

This report is recorded in a follow-up documentation commit so it can name the immutable implementation commit above.

## Modified files

- `CineBar/Sources/CineBar/LocalLibraryView.swift`
  - Added an explicit `查看详情` row action.
  - Added confirmed Movie/TV bridge routing through `LocalLibraryDetailBridge`, `MovieStore.select(_:)`, and `selectTV(_:)` while keeping `isShowingLocalLibrary` true.
  - Added `LocalLibraryFileDetailView` with filename, relative path, folder, file size, watched/watchlist state, top-left close, and a manual match action; it contains no external score, cast, still, or trailer UI.
  - Added persisted-match verification before opening external details.
  - Sequenced file-detail dismissal before presenting matching to avoid overlapping-sheet presentation races.
- `CineBar/Sources/CineBar/main.swift`
  - Moved Local Library search/category/status state into `ContentView` so it survives detail routing.
  - Reordered routes so selected Movie/TV details precede the Local Library list.
- `CineBar/Tools/tests/app-branding.test.mjs`
  - Added source assertions for the detail action, local-file detail fields, absence of invented external fields, bridge calls, persistence guard, sheet sequencing, route precedence, and retained filter state.

## TDD evidence

- Initial targeted Node test: exit 1, expected failure because `LocalLibraryFileDetailView` was absent.
- Sheet sequencing assertion: exit 1 before `onDismiss: presentPendingMatch` was implemented, then passed.
- Persistence guard assertion: exit 1 before the post-`confirmMatch` store read-back was implemented, then passed.

## Final verification

Run from `/Users/bruce/Documents/Codex/2026-07-25/you/work/.worktrees/test-rating-lock-multiscreen`:

```bash
mkdir -p /tmp/cinebar-tests
xcrun swiftc -parse-as-library -D CINEBAR_TEST CineBar/Sources/CineBar/*.swift CineBar/Tests/RegressionBehaviorTests.swift -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
node --test CineBar/Tools/tests/*.test.mjs
git diff --check
```

Actual result: exit 0. Swift compilation succeeded with no diagnostics; the regression executable exited successfully with no failures; Node reported 15 tests, 15 passed, 0 failed; `git diff --check` reported no errors.

## Concerns

- Task 4 owns translations for the newly introduced labels. This commit deliberately does not modify localization files, so non-Chinese locales temporarily fall back to the Chinese localization keys until Task 4 lands.
- Verification covers Swift compilation/regression behavior and source-level UI contracts. No interactive macOS GUI pass was performed in this task.
- Existing untracked build artifacts and `task-7-report.md` in the shared worktree were not modified or staged.
