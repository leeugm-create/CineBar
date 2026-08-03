# Task 6 report — CineBar Build 23 Local Library

## Delivered

- Added the required Local Library terms to all five `Localizable.strings` files.
- Updated application build metadata to `0.8.3` / Build 23 and website/share metadata to `0.8.3-test.7` / Build 23.
- Added Build 23 release notes and Chinese plus English installation guidance.
- Documented folder permission, refresh, confirmation-only TMDB matching, local-only
  playback (IINA, VLC, then the macOS default player), offline playback, and file
  relocation troubleshooting. The documentation explicitly says no uploads,
  downloads, or pirated sources are provided.
- Preserved the existing signed Build 22 Sparkle appcast. Build 23 is documented as
  a manual GitHub Releases download until a signed appcast/archive is published. No Build 23 archive,
  length, or EdDSA signature was available, so publishing a fabricated appcast
  entry would be unsafe. The share manifest now tracks Build 23 independently.
- LocalLibraryView now uses explicit localized keys and format strings for every
  user-visible Local Library label, status, prompt, error, and match-sheet action.

## Verification

- `xcrun swiftc -parse-as-library -D CINEBAR_TEST ... && /tmp/cinebar-tests/CineBarRegressionTests` — passed.
- `node --test CineBar/Tools/tests/*.test.mjs` — 9 passed.
- `node --test CineBarShare/tests/share-worker.test.mjs` — 12 passed.
- `(cd CineBarWebsite && npm test)` — build plus 14 tests passed.
- `git diff --check` — passed.
- Production `xcrun swiftc -parse-as-library -typecheck CineBar/Sources/CineBar/*.swift`
  cannot run standalone because it lacks the Sparkle framework search path and fails
  at `import Sparkle`; this is unrelated to Task 6 source changes.

No deployment was performed.
