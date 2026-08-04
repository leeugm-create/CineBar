# Task 5 Report: CineBar 0.8.3-test.11 / Build 27

## Status

Complete. Build 27 release metadata, localized in-app New Features copy, English and Chinese installation guides, release notes, website version/download copy, health metadata, signed Sparkle appcast, and immutable website download archive are synchronized. The public `cinebar.cc` deployment is live and was verified from the network.

The current Build 27 artifact was rebuilt during review remediation. The remediation section at the end of this report supersedes the initial artifact hash, manifest commit, enclosure length, and deployment identifiers recorded below.

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

## Review remediation: explicit app code-signing disclosure

### Finding and fix

The packaged HTML/TXT guides and English guide disclosed that Build 27 was not notarized, but did not explicitly disclose that `CineBar.app` itself used only ad-hoc code signing and was not signed with an Apple Developer ID certificate. The release notes mentioned an independent update signature without explaining that Sparkle EdDSA verifies only the update archive and does not provide Developer ID code signing or notarization.

The following files now use consistent, explicit wording:

- `CineBar/INSTALL.md`
- `CineBar/请先阅读-测试版安装说明.html`
- `CineBar/请先阅读-测试版安装说明.txt`
- `CineBar/ReleaseNotes/0.8.3-test.11-Build-27.txt`

Each states that the application bundle uses only ad-hoc/temporary code signing, is not Apple Developer ID signed, and is not Apple notarized. They separately state that Sparkle EdDSA verifies the downloaded update archive and cannot substitute for the app's code-signing identity or notarization.

TDD evidence:

```bash
node --test --test-name-pattern='ad-hoc app signing' CineBar/Tools/tests/app-branding.test.mjs
```

Before the wording fix, the new test failed because `INSTALL.md` did not contain `ad-hoc`. After the minimal four-document fix, it reported 1 test passed and 0 failed.

Build-input fix commit:

- `25278eac60da5aa4b9723364cf12cf615a26dc00` — `fix: disclose Build 27 ad-hoc signing`

### Rebuilt package and provenance

The same Build 27 version and URL were retained, but the archive was rebuilt because the corrected guides and release notes are tracked BuildManifest inputs.

- Artifact: `dist/CineBar-0.8.3-test-build-27-universal.zip`
- Public tracked copy: `CineBarWebsite/public/downloads/CineBar-0.8.3-test-build-27-universal.zip`
- Size: `5,994,753` bytes
- Current SHA-256: `7b7e9dbc38487dd20b4d8bc5f7f41fd1f7060561bd967df28103bc28aa1dc41d`
- Architectures: `x86_64 arm64`
- Embedded manifest commit: `25278eac60da5aa4b9723364cf12cf615a26dc00`
- Embedded source tree: `845111984458340db481ddb42002d0dd12f979c0`
- Manifest version/build/status: `0.8.3` / `27` / `clean`

Commands:

```bash
CineBar/Tools/check_build_provenance.sh "$(pwd)" 0.8.3 27 CineBar/Sources/CineBar CineBar/Info.plist CineBar/PkgInfo CineBar/Assets CineBar/ReleaseNotes CineBar/INSTALL.md CineBar/README.md CineBar/请先阅读-测试版安装说明.html CineBar/请先阅读-测试版安装说明.txt CineBar/Tools/build_test_package.sh CineBar/Tools/check_build_provenance.sh
CineBar/Tools/build_test_package.sh
codesign --verify --deep --strict --verbose=2 <extracted-build>/CineBar.app
lipo -archs <extracted-build>/CineBar.app/Contents/MacOS/CineBar
```

Actual result: provenance reported clean commit `25278ea` and source tree `8451119`; both architecture compiles completed; package creation exited 0; extracted application code-signature verification passed; `lipo` reported `x86_64 arm64`; delivery and embedded manifests were identical. Direct checks of the packaged HTML/TXT guides and release notes found the required ad-hoc, Apple Developer ID, notarization, and Sparkle EdDSA disclosures.

### Re-signed appcast and publication

Because the release remains Build 27, the prior Build 27 item was removed before running the existing `publish_sparkle_update.sh` workflow; the script then generated a fresh Build 27 item and EdDSA signature from the reviewed release-notes file. Historical Build 26–23 items were preserved.

Current first enclosure:

- build `27`
- short version `0.8.3-test.11`
- URL `https://cinebar.cc/downloads/CineBar-0.8.3-test-build-27-universal.zip`
- length `5994753`
- order `27, 26, 25, 24, 23`

Publishing commit:

- `515dcec` — `release: refresh Build 27 signing disclosure package`

The exact tracked website tree was deployed through the existing public Wrangler workflow:

- Cloudflare version ID: `d48209fb-ba7b-4864-8c07-936b84c1400c`
- Public targets: `https://cinebar.cc` and `https://cinebar-website.leeugm.workers.dev`
- Sites source staging commit: `49df512b16113e04f854c5835d6e09f76ef34669`
- Sites project version: 4
- Sites owner-only deployment: `https://cinebar-official.brucelee8282.chatgpt.site`

### Final and live verification

Pre-publication verification results:

- Node: 34 tests passed, 0 failed.
- Swift full-source compilation and regression executable: exit 0.
- Website: production build succeeded; 17 tests passed, 0 failed; deploy dry-run exited 0.
- ESLint: exit 0 with the existing `@next/next/no-img-element` warning and no errors.
- `git diff --check`: exit 0.

Live verification downloaded the public appcast and ZIP again and performed these checks:

```bash
curl --fail --location https://cinebar.cc/appcast.xml
curl --fail --location https://cinebar.cc/downloads/CineBar-0.8.3-test-build-27-universal.zip
CineBar/.vendor/Sparkle-2.9.2/bin/sign_update --verify <public-zip> <live-enclosure-signature>
shasum -a 256 dist/CineBar-0.8.3-test-build-27-universal.zip CineBarWebsite/public/downloads/CineBar-0.8.3-test-build-27-universal.zip <public-zip>
```

Actual result:

- `/`, `/health`, `/appcast.xml`, and the Build 27 ZIP each returned HTTP 200.
- The live appcast was byte-identical to the committed appcast and its first item was Build 27.
- Sparkle `sign_update --verify` accepted the live enclosure signature for the freshly downloaded ZIP.
- Local artifact, tracked website archive, and public download all had SHA-256 `7b7e9dbc38487dd20b4d8bc5f7f41fd1f7060561bd967df28103bc28aa1dc41d`.
- The public ZIP was extracted again; both Chinese installation guides contained the explicit ad-hoc, non-Developer ID, non-notarized, and Sparkle EdDSA boundary wording; the extracted app passed `codesign --verify --deep --strict`; its BuildManifest pointed to clean commit `25278ea`.

### Remaining concerns

- Build 27 is still an ad-hoc signed, non-Developer ID, non-notarized test build. Neither the Sparkle EdDSA signature nor successful code-signature verification changes that status.
- No interactive Sparkle installer UI or first-launch Gatekeeper walkthrough was performed.
- Reusing the same Build 27 URL required replacing the previously published archive and appcast signature. Current local, tracked, and public bytes are synchronized and verified, but caches holding the earlier Build 27 archive could temporarily retain the prior bytes despite `must-revalidate` headers.
- Existing unrelated untracked/ignored artifacts were preserved; no cleanup was performed.

## Review remediation: stable ASCII installation entry

### Finding and TDD fix

The delivery archive retained both Chinese installation guides, and `ditto` could extract them correctly, but a generic `unzip -l` listing did not render their filenames reliably in this environment. That made the archive lack a stable, immediately discoverable installation entry for tools or users that do not preserve the Unicode names.

The package workflow now copies the existing English `CineBar/INSTALL.md` to the delivery root as `INSTALL.md` while preserving both Chinese guides. A focused Node regression test asserts all three copy operations. The test first failed because the package script had no `INSTALL.md` copy operation, then passed after the one-line packaging fix.

Build-input fix commit:

- `5c4ac71f475dabafc8edf862cafd3b37a1e59555` — `fix: package ASCII installation guide`

### Rebuilt package and provenance

The release remains version `0.8.3`, Build `27`, short version `0.8.3-test.11`, and uses the same public URL. This rebuild supersedes the earlier Build 27 archive hash recorded above.

- Artifact: `dist/CineBar-0.8.3-test-build-27-universal.zip`
- Public tracked copy: `CineBarWebsite/public/downloads/CineBar-0.8.3-test-build-27-universal.zip`
- Size: `5,996,531` bytes
- Current SHA-256: `4a69faf3352e7f05f3219e0f28cea2745531d4fed903c8559c22fa26e24c4adc`
- Architectures: `x86_64 arm64`
- Embedded manifest commit: `5c4ac71f475dabafc8edf862cafd3b37a1e59555`
- Embedded source tree: `534ad5a420c233a18a74c82cc3779f688f6609a8`
- Manifest version/build/status: `0.8.3` / `27` / `clean`

`unzip -Z1` showed the exact ASCII entry `CineBar-0.8.3-test-build-27/INSTALL.md`. A separate `ditto` extraction confirmed these three root files and byte-compared each one with its tracked source:

- `INSTALL.md`
- `请先阅读-测试版安装说明.html`
- `请先阅读-测试版安装说明.txt`

The extracted application passed `codesign --verify --deep --strict --verbose=2`; `lipo` reported `x86_64 arm64`; the delivery and embedded `BuildManifest.json` files were identical.

### Re-signed appcast and publication

The prior first Build 27 item was replaced and the existing publishing workflow generated a new EdDSA signature for the rebuilt archive. Historical Build 26–23 items were not changed or deleted.

Current first enclosure:

- build `27`
- short version `0.8.3-test.11`
- URL `https://cinebar.cc/downloads/CineBar-0.8.3-test-build-27-universal.zip`
- length `5996531`
- order `27, 26, 25, 24, 23`

Publishing commit:

- `2b2cf0c2eac2d1d707ad27fa6a314e3e55d7d964` — `release: refresh Build 27 installation bundle`

Deployment records:

- Cloudflare version ID: `f89de3d1-298e-48fd-bd9f-b7ea44c0e815`
- Public targets: `https://cinebar.cc` and `https://cinebar-website.leeugm.workers.dev`
- Sites source staging commit: `3f05deecf4fca28f0a8fcb7280384eeb4f49834b`
- Sites source tree: `e7e6075ec841fd691aa156c5ee5e91fb0ec982b7`
- Sites project version: 5
- Sites deployment ID: `appgdep_6a7207791b188191bc09593dbde0474f`
- Sites owner-only deployment: `https://cinebar-official.brucelee8282.chatgpt.site`

### Verification evidence

Before rebuilding, all 35 Node tests passed, the full Swift source compiled for the test harness, the Swift regression executable exited 0, and `git diff --check` exited 0. After publishing, all 35 Node tests passed again.

Fresh online verification returned HTTP 200 for `/`, `/health`, `/appcast.xml`, and the Build 27 ZIP. The live appcast was byte-identical to the committed appcast. Sparkle `sign_update --verify` accepted the first enclosure signature for the freshly downloaded archive. The local artifact, tracked public copy, and fresh public download all had SHA-256 `4a69faf3352e7f05f3219e0f28cea2745531d4fed903c8559c22fa26e24c4adc`.

The public ZIP was extracted with `ditto`; all three root installation guides existed and were byte-identical to their tracked sources. The extracted app passed strict deep code-signature verification, remained universal `x86_64 arm64`, and its matching manifests pointed to clean build-input commit `5c4ac71f475dabafc8edf862cafd3b37a1e59555` and source tree `534ad5a420c233a18a74c82cc3779f688f6609a8`.

### Remaining concerns

- Build 27 remains ad-hoc signed, is not signed with Apple Developer ID, and is not Apple notarized. Sparkle EdDSA authenticates only the update archive.
- Replacing the same Build 27 URL again introduces cache risk: a stale intermediary or client may temporarily retain an earlier Build 27 byte sequence and signature pair.
- No interactive Sparkle installer, first-launch Gatekeeper, or manual GUI installation walkthrough was performed.
- Existing unrelated untracked/ignored artifacts were preserved; no cleanup was performed.
