# Task 3 Report: Local Library Store

## Commit

`d38d585 feat: persist local library state`

Round 1 scope-lifecycle fix: `4fe9cb4 fix: retain folder scope while reattaching`

## Implemented

- Added the main-actor `LocalLibraryStore` with published folder, entry,
  scan-state, progress, and user-message state.
- Loads and saves `LocalLibrarySnapshot` through `LocalLibraryPersistence` for
  every successful folder, entry, and refresh mutation.
- Creates and de-duplicates folder bookmarks; refreshes bookmarked roots using
  the Task 2 scanner and merger, preserving metadata, watched, watchlist, and
  recent-open state while retaining missing and unavailable-root results.
- Keeps filesystem scanning off the main actor and ignores overlapping refresh
  requests until the active scan finishes.
- Reattaches an entry only when the candidate file signature matches and it is
  within an authorized folder, preserving user and metadata state.
- Holds the resolved folder security scope through signature validation,
  persistence, and published-state updates; a mismatched candidate does not
  mutate the entry.
- Added regression coverage for folder de-duplication, discovery on refresh,
  persisted watched/watchlist/recent/metadata state, reattachment, and an
  overlapping-refresh request.
- Added coverage for reading a candidate file's resource values inside the
  authorized-folder scope callback.

## Verification

```bash
mkdir -p /tmp/cinebar-tests
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
```

The compiler and executable both exited with status 0. `git diff --cached
--check` was clean before the commit.
