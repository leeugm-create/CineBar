# Task 4 Report: Local Playback and Metadata Matching

## Implemented

- Added deterministic IINA, VLC, then system-player resolution and a launcher
  that accepts local `file:` URLs only.
- Added a TMDB-backed match service with injectable search closures for tests.
  It produces ranked candidates without mutating local-library entries.
- Added regression coverage for player priority and fallback, encoded local
  paths, remote URL rejection, candidate field preservation and confidence,
  movie/TV routing, empty-query behavior, and unmatched-entry preservation.

## Verification

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
```

Both commands exited with status 0. The non-test `-typecheck` command remains
blocked by the workspace's unavailable Sparkle framework, which predates and is
outside this task's scope.

## Round 1 Fix

- Player launches now wait for the `NSWorkspace` completion handler and only
  count as successful when it reports an application and no error.
- A five-second callback timeout is treated as failure, so the next provider
  can be attempted rather than reporting an unverified launch as successful.
