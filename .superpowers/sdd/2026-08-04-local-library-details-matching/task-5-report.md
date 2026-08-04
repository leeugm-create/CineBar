# Task 5 Report: CineBar 0.8.3-test.11 / Build 27

## Status

Complete. Build 27 release metadata, localized in-app New Features copy, English and Chinese installation guides, release notes, website version/download copy, health metadata, signed Sparkle appcast, and immutable website download archive are synchronized. The public `cinebar.cc` deployment is live and was verified from the network.

This remains a test build. The application bundle is ad-hoc signed for integrity and the update archive has a CineBar Sparkle EdDSA signature, but it is not Apple Developer ID signed and has not been Apple notarized.

## Commits

- `170e0f16dbd73aae99f2a6c43d8c2c033b610a24` — `release: prepare CineBar Build 27 test package`
  - Clean tracked inputs used by `build_test_package.sh` and recorded in the package `BuildManifest.json`.
- `5afa47fcf070ea840ebf80cadf3221f2c6217106` — `release: publish CineBar Build 27 update`
  - Adds the signed Build 27 appcast entry and the exact immutable ZIP under the website download path.
- `8fa155244fb62cdabaed6b951d40e4ee0cccd53e` — Sites-source staging commit whose root tree is exactly `CineBarWebsite` at `5afa47f`; this commit exists only in the site-bound source repository and does not change the product branch.

## Package and provenance

- Local artifact: `dist/CineBar-0.8.3-test-build-27-universal.zip`
- Public tracked copy: `CineBarWebsite/public/downloads/CineBar-0.8.3-test-build-27-universal.zip`
- Size: `5,994,542` bytes
- SHA-256: `aabae5acb02a2b5b6e0138ad1b5fac659789b18df9199fdf3f29b4c1ed9518cc`
- Architectures: `x86_64 arm64`
- Bundle metadata: `CFBundleShortVersionString=0.8.3`, `CFBundleVersion=27`
- Sparkle feed URL retained: `https://cinebar.cc/appcast.xml`
- Sparkle public key retained and matched against `generate_keys -p`: `R7z+aK5MYtIFkCD9UgYM3sqn3EtwYZn84Piq3l0eVlk=`
- Embedded manifest:
  - commit `170e0f16dbd73aae99f2a6c43d8c2c033b610a24`
  - source tree `36a2f8a5b02dba446b7a1f8718fec3302de59cb7`
  - version `0.8.3`, build `27`, status `clean`

The package contains `CineBar.app`, all release notes including `0.8.3-test.11-Build-27.txt`, both Chinese installation guides, the delivery-level `BuildManifest.json`, and the identical manifest under `CineBar.app/Contents/Resources`. `codesign --verify --deep --strict` passed for the extracted ad-hoc signed app, and `lipo -archs` reported both required architectures.

## Sparkle and appcast verification

`CineBar/Tools/publish_sparkle_update.sh` generated the appcast only after package review. XML validation passed and enclosure order is `27, 26, 25, 24, 23`. The first enclosure has:

- version `27`
- short version `0.8.3-test.11`
- URL `https://cinebar.cc/downloads/CineBar-0.8.3-test-build-27-universal.zip`
- length `5994542`

`sign_update --verify` accepted the first enclosure's EdDSA signature for both the local archive and a freshly downloaded public archive. The downloaded archive and local artifact have the same SHA-256 above. The live appcast is byte-identical to the committed appcast.

## Verification commands and actual results

Run from the worktree root unless noted:

```bash
node --test CineBar/Tools/tests/*.test.mjs CineBarWebsite/tests/*.test.mjs
mkdir -p /tmp/cinebar-task5-tests
xcrun swiftc -parse-as-library -D CINEBAR_TEST CineBar/Sources/CineBar/*.swift CineBar/Tests/RegressionBehaviorTests.swift -o /tmp/cinebar-task5-tests/CineBarRegressionTests
/tmp/cinebar-task5-tests/CineBarRegressionTests
for locale in zh-Hans zh-Hant en ja ko; do plutil -lint "CineBar/Assets/Localization/$locale.lproj/Localizable.strings"; done
git diff --check
```

Actual result: Node reported 33 tests passed and 0 failed. Swift full-source compilation and the regression executable exited 0 without diagnostics or failed preconditions. All five localization files reported `OK`. `git diff --check` exited 0.

Website verification from `CineBarWebsite`:

```bash
npm test
npm run lint
npm run deploy:dry-run
```

Actual result: production build succeeded; 17 website tests passed and 0 failed; deploy dry-run exited 0. ESLint exited 0 with one existing `@next/next/no-img-element` warning for the established brand image and no errors.

Package/provenance verification:

```bash
CineBar/Tools/check_build_provenance.sh "$(pwd)" 0.8.3 27 CineBar/Sources/CineBar CineBar/Info.plist CineBar/PkgInfo CineBar/Assets CineBar/ReleaseNotes CineBar/INSTALL.md CineBar/README.md CineBar/请先阅读-测试版安装说明.html CineBar/请先阅读-测试版安装说明.txt CineBar/Tools/build_test_package.sh CineBar/Tools/check_build_provenance.sh
CineBar/Tools/build_test_package.sh
unzip -l dist/CineBar-0.8.3-test-build-27-universal.zip
```

Actual result: the pre-build provenance command reported clean commit `170e0f1` and source tree `36a2f8a`; the build compiled Apple silicon and Intel binaries, verified the nested signatures, and created the expected ZIP. The package content, manifest, architecture, Bundle metadata, app signature, archive hash, appcast order, and Sparkle signature were then checked explicitly as described above.

## Deployment

- Sites project version 3 was successfully deployed owner-only to `https://cinebar-official.brucelee8282.chatgpt.site`.
- The exact website source was publicly deployed through the existing Wrangler workflow to `https://cinebar.cc` and `https://cinebar-website.leeugm.workers.dev`.
- Cloudflare deployment version ID: `651f485d-ebec-4540-a520-df99a05fef3d`.
- Public verification returned HTTP 200 for `/`, `/health`, `/appcast.xml`, and `/downloads/CineBar-0.8.3-test-build-27-universal.zip`. The homepage and health route advertise Build 27; the appcast and ZIP passed the byte/hash/signature checks above.

Two attempts to attach a local Sites build archive timed out in the file-blob upload channel after 60 seconds (first with a 52 MB archive that also contained preserved ignored historical ZIPs, then with a 31 MB exact-source archive). No version was created by either failed upload. The official source-based save path then succeeded. An initial source-based deployment version failed with `missing package.json` because the bound repo received the monorepo root; the follow-up fast-forward site-root commit corrected the source layout and deployed successfully. These transient failures did not affect the public Cloudflare deployment.

## Concerns

- No interactive macOS GUI pass, live TMDB matching session, Sparkle installer UI run, or Apple notarization assessment was performed. Swift regression coverage, package inspection, code-signature verification, Sparkle signature verification, and live HTTP artifact verification were performed.
- The application uses ad-hoc signing and is explicitly documented as a non-notarized test build. It must not be described as an Apple-notarized or formal stable release.
- The package manifest intentionally points to clean build-input commit `170e0f1`; the later `5afa47f` commit only publishes that already-reviewed immutable ZIP and its signed appcast.
- Existing unrelated untracked/ignored artifacts were preserved. No cleanup was performed. Temporary verification and exact-source build directories under the system temporary directory were also left in place because the command safety layer rejected automatic cleanup traps.
