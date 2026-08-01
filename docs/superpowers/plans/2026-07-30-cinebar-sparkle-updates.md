# CineBar Sparkle Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first CineBar build that securely discovers, verifies, installs, and relaunches application updates inside the app, while preserving a one-time browser migration path for Build 16.

**Architecture:** Integrate the official Sparkle 2.9.2 binary framework into the existing direct `swiftc` build, use Sparkle's standard updater UI and EdDSA archive signatures, and publish an appcast from `cinebar.cc`. Keep the existing JSON manifest only for Build 16 migration.

**Tech Stack:** Swift/AppKit/SwiftUI, Sparkle 2.9.2, Ed25519 signatures, Universal macOS app bundle, GitHub Releases, Sites static appcast, Node and Swift regression tests.

## Global Constraints

- The first Sparkle-enabled build must use `CFBundleVersion` 17 or higher.
- The Sparkle dependency is pinned to version `2.9.2`.
- The official Sparkle archive SHA-256 is `1cb340cbbef04c6c0d162078610c25e2221031d794a3449d89f2f56f4df77c95`.
- The appcast URL is exactly `https://cinebar.cc/appcast.xml`.
- Update archives must be signed with Sparkle EdDSA.
- The EdDSA private key must never be committed, uploaded to GitHub, or stored on the website server.
- Update installation must require user confirmation while CineBar lacks Developer ID signing and notarization.
- Signature failure must never fall back to installing an unverified archive.
- Build 16 remains a manual one-time migration through GitHub Releases.
- Existing Build 16 packages and application behavior must not be overwritten.

---

## File Structure

- `CineBar/Sources/CineBar/UpdaterService.swift`: Sparkle controller wrapper and user-driven update commands.
- `CineBar/Sources/CineBar/main.swift`: settings UI wiring and removal of the obsolete JSON-only update UI for new builds.
- `CineBar/Info.plist`: Sparkle feed URL, EdDSA public key, and update defaults.
- `CineBar/Tools/fetch_sparkle.sh`: pinned download and checksum validation.
- `CineBar/Tools/build_test_package.sh`: link and embed Sparkle in both architectures, preserve framework symlinks, sign nested code, and create a Universal ZIP.
- `CineBar/Tools/publish_sparkle_update.sh`: sign one release archive and generate an appcast fragment without exposing the private key.
- `CineBar/Tests/RegressionBehaviorTests.swift`: update preference and notification regression behavior.
- `CineBarWebsite/public/appcast.xml`: signed update feed.
- `CineBarShare/worker.js`: Build 16 `download_url` migration link only.
- `CineBarShare/tests/share-worker.test.mjs`: Build 16 migration assertion.

### Task 1: Fetch and Embed a Pinned Sparkle Distribution

**Files:**
- Create: `CineBar/Tools/fetch_sparkle.sh`
- Modify: `CineBar/Tools/build_test_package.sh`

**Interfaces:**
- Consumes: Sparkle 2.9.2 official release archive.
- Produces: `CineBar/.vendor/Sparkle-2.9.2/Sparkle.framework` and a distributable app containing `Contents/Frameworks/Sparkle.framework`.

- [ ] **Step 1: Write a failing fetch-script contract check**

Run:

```bash
test -x CineBar/Tools/fetch_sparkle.sh
```

Expected: FAIL because the script does not exist.

- [ ] **Step 2: Implement the pinned fetcher**

Create `CineBar/Tools/fetch_sparkle.sh` with:

```bash
#!/bin/bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
app_dir=$(cd "$script_dir/.." && pwd)
version="2.9.2"
expected_sha="1cb340cbbef04c6c0d162078610c25e2221031d794a3449d89f2f56f4df77c95"
vendor_root="$app_dir/.vendor"
destination="$vendor_root/Sparkle-$version"
archive="$vendor_root/Sparkle-$version.tar.xz"
url="https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"

if [[ -d "$destination/Sparkle.framework" && -x "$destination/bin/sign_update" ]]; then
  exit 0
fi

mkdir -p "$vendor_root"
curl --fail --location --proto '=https' --tlsv1.2 "$url" --output "$archive"
actual_sha=$(shasum -a 256 "$archive" | awk '{print $1}')
[[ "$actual_sha" == "$expected_sha" ]] || {
  echo "Sparkle checksum mismatch" >&2
  exit 1
}

rm -rf "$destination"
mkdir -p "$destination"
tar -xJf "$archive" -C "$destination" --strip-components=1
test -d "$destination/Sparkle.framework"
test -x "$destination/bin/sign_update"
```

Mark it executable:

```bash
chmod 755 CineBar/Tools/fetch_sparkle.sh
```

- [ ] **Step 3: Fetch and verify the framework**

Run:

```bash
CineBar/Tools/fetch_sparkle.sh
codesign --verify --deep --strict CineBar/.vendor/Sparkle-2.9.2/Sparkle.framework
```

Expected: the checksum matches and code-sign verification succeeds.

- [ ] **Step 4: Update the package builder**

Modify `build_test_package.sh` to:

1. call `fetch_sparkle.sh`;
2. read `CFBundleShortVersionString` and `CFBundleVersion` from `Info.plist`;
3. name the output `CineBar-<version>-test-build-<build>-universal.zip`;
4. add `-F "$sparkle_dir" -framework Sparkle`;
5. add linker rpath `-Xlinker -rpath -Xlinker @executable_path/../Frameworks`;
6. create `Contents/Frameworks`;
7. copy `Sparkle.framework` with `ditto` so symlinks and permissions survive;
8. sign nested Sparkle XPC services and framework before signing `CineBar.app`;
9. verify with `codesign --verify --deep --strict`.

Derive the package name with:

```bash
version=$(/usr/libexec/PlistBuddy \
  -c "Print :CFBundleShortVersionString" "$info_plist")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist")
package_name="CineBar-$version-test-build-$build"
```

The two compile commands must include:

```bash
-F "$sparkle_dir" \
-framework Sparkle \
-Xlinker -rpath \
-Xlinker @executable_path/../Frameworks
```

The copy must use:

```bash
ditto "$sparkle_dir/Sparkle.framework" \
  "$contents_dir/Frameworks/Sparkle.framework"
```

- [ ] **Step 5: Build and inspect the test package**

Run:

```bash
CineBar/Tools/build_test_package.sh
unzip -l dist/CineBar-0.8.2-test-build-16-universal.zip | \
  grep Sparkle.framework
```

Expected: the app builds for both architectures and the archive contains
Sparkle framework and its installer helpers.

- [ ] **Step 6: Commit**

```bash
git add CineBar/Tools/fetch_sparkle.sh CineBar/Tools/build_test_package.sh
git commit -m "build: embed pinned Sparkle updater"
```

### Task 2: Replace JSON-Only Update UI with Sparkle

**Files:**
- Create: `CineBar/Sources/CineBar/UpdaterService.swift`
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Info.plist`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:**
- Consumes: embedded `Sparkle.framework`, `SUFeedURL`, and `SUPublicEDKey`.
- Produces: `UpdaterService.shared.checkForUpdates()` and Sparkle standard update UI.

- [ ] **Step 1: Add failing pure update-preference tests**

Add a pure helper to the planned API:

```swift
enum UpdatePolicy {
    static let feedURL = "https://cinebar.cc/appcast.xml"
    static let automaticChecksDefaultsKey = "SUEnableAutomaticChecks"
}
```

Add assertions to `RegressionBehaviorTests.swift`:

```swift
precondition(UpdatePolicy.feedURL == "https://cinebar.cc/appcast.xml")
precondition(UpdatePolicy.automaticChecksDefaultsKey == "SUEnableAutomaticChecks")
```

- [ ] **Step 2: Run Swift regression tests to verify they fail**

Run:

```bash
mkdir -p /tmp/cinebar-tests
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
```

Expected: FAIL because `UpdatePolicy` does not exist.

- [ ] **Step 3: Implement the updater wrapper**

Create `UpdaterService.swift`:

```swift
import Foundation

enum UpdatePolicy {
    static let feedURL = "https://cinebar.cc/appcast.xml"
    static let automaticChecksDefaultsKey = "SUEnableAutomaticChecks"
}

#if !CINEBAR_TEST
import Sparkle

@MainActor
final class UpdaterService {
    static let shared = UpdaterService()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#endif
```

- [ ] **Step 4: Wire the settings UI**

In `main.swift`:

- remove `UpdateManifest`, `availableUpdate`, JSON manifest fetching, and the
  obsolete download-only card for new builds;
- keep unrelated `MovieStore` networking and Build 16-compatible server code;
- change “立即检查” to call `UpdaterService.shared.checkForUpdates()`;
- bind the automatic-check toggle to
  `UpdaterService.shared.automaticallyChecksForUpdates`;
- remove the `ContentView.onAppear` JSON update check;
- show explanatory text `更新包会在安装前验证 CineBar 的独立签名。`.

The resulting button action must be:

```swift
Button("立即检查") {
    UpdaterService.shared.checkForUpdates()
}
.disabled(!UpdaterService.shared.canCheckForUpdates)
```

- [ ] **Step 5: Generate and back up the EdDSA key**

On the release Mac, run:

```bash
CineBar/.vendor/Sparkle-2.9.2/bin/generate_keys
```

Store the private key in the login Keychain. Export one encrypted offline
backup using Sparkle's supported key export option, store it outside the repo,
and verify `git status --short` shows no key file.

- [ ] **Step 6: Configure Sparkle metadata with the generated public key**

Capture the exact base64 public key printed by `generate_keys` in a shell
variable named `sparkle_public_key`, validate that it is non-empty, then run:

```bash
plutil -replace SUFeedURL \
  -string "https://cinebar.cc/appcast.xml" CineBar/Info.plist
plutil -replace SUPublicEDKey \
  -string "$sparkle_public_key" CineBar/Info.plist
plutil -replace SUEnableAutomaticChecks -bool YES CineBar/Info.plist
plutil -replace SUAutomaticallyUpdate -bool NO CineBar/Info.plist
plutil -replace CFBundleShortVersionString -string "0.8.3" CineBar/Info.plist
plutil -replace CFBundleVersion -string "17" CineBar/Info.plist
```

If a key is absent, use `plutil -insert` for that one key instead of replacing
it. Verify the feed URL and public key with `plutil -p CineBar/Info.plist`.
Never insert the private key.

- [ ] **Step 7: Run regressions and compile both architectures**

Run:

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
CineBar/Tools/build_test_package.sh
```

Expected: Swift regressions PASS and the Universal app builds.

- [ ] **Step 8: Commit**

```bash
git add CineBar/Sources/CineBar/UpdaterService.swift \
  CineBar/Sources/CineBar/main.swift \
  CineBar/Info.plist \
  CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "feat: install signed updates with Sparkle"
```

### Task 3: Publish a Signed Appcast and Preserve Build 16 Migration

**Files:**
- Create: `CineBar/Tools/publish_sparkle_update.sh`
- Create: `CineBarWebsite/public/appcast.xml`
- Modify: `CineBarShare/worker.js`
- Modify: `CineBarShare/tests/share-worker.test.mjs`

**Interfaces:**
- Consumes: one uploaded GitHub Release ZIP, its HTTPS asset URL, EdDSA key in Keychain, version, Build, publication date, and file length.
- Produces: a signed `appcast.xml` and a Build 16 JSON manifest pointing to GitHub Releases.

- [ ] **Step 1: Update the failing Build 16 migration assertion**

Change the existing manifest test to expect:

```js
assert.equal(body.version, "0.8.3");
assert.equal(body.build, 17);
assert.equal(
  body.download_url,
  "https://github.com/leeugm-create/CineBar/releases",
);
```

- [ ] **Step 2: Run the Share Worker test to verify it fails**

Run:

```bash
cd CineBarShare
node --test tests/share-worker.test.mjs
```

Expected: FAIL because the current `download_url` is `null`.

- [ ] **Step 3: Publish the Build 17 migration notice for Build 16**

After the Build 17 GitHub asset exists, update `/updates/latest.json` to:

```js
version: "0.8.3",
build: 17,
published_at: "2026-07-30",
download_url: "https://github.com/leeugm-create/CineBar/releases",
notes: [
  "新增经过 CineBar 独立签名验证的应用内更新",
  "后续版本可在 CineBar 内安装并重新启动",
  "Build 16 用户本次需要从 GitHub Releases 手动安装",
],
```

Do not deploy this manifest before the Build 17 archive is downloadable.

- [ ] **Step 4: Create the signed-appcast publisher**

Create a script accepting:

```text
publish_sparkle_update.sh ARCHIVE DOWNLOAD_URL VERSION BUILD PUBLISHED_AT
```

It must:

- reject non-HTTPS download URLs;
- reject a build that is not a positive integer;
- call Sparkle `bin/sign_update` without passing the private key on the command
  line;
- capture `sparkle:edSignature` and `length`;
- write a complete RSS appcast to
  `CineBarWebsite/public/appcast.xml`;
- XML-escape every input string;
- leave the existing appcast untouched when signing fails.

The script must render the enclosure from its validated shell variables:

```xml
<enclosure
  url="${escaped_download_url}"
  sparkle:version="${build}"
  sparkle:shortVersionString="${escaped_version}"
  length="${archive_length}"
  type="application/octet-stream"
  sparkle:edSignature="${ed_signature}"/>
```

- [ ] **Step 5: Test invalid inputs**

Run:

```bash
invalid_archive=$(mktemp "${TMPDIR:-/tmp}/cinebar-invalid.XXXXXX.zip")
printf 'not a release archive' > "$invalid_archive"
! CineBar/Tools/publish_sparkle_update.sh \
  "$invalid_archive" http://invalid.example/file.zip 0.8.3 17 2026-07-30
! CineBar/Tools/publish_sparkle_update.sh \
  "$invalid_archive" https://example.com/file.zip 0.8.3 not-a-build 2026-07-30
```

Expected: both commands fail without modifying `appcast.xml`.

- [ ] **Step 6: Publish only after the GitHub asset exists**

Create the GitHub Pre-release, upload the exact Universal ZIP, copy its final
HTTPS asset URL, then run the publisher with Build 17 or higher. Verify:

```bash
xmllint --noout CineBarWebsite/public/appcast.xml
grep -F 'sparkle:edSignature=' CineBarWebsite/public/appcast.xml
grep -F 'sparkle:version="17"' CineBarWebsite/public/appcast.xml
```

- [ ] **Step 7: Deploy both compatibility paths**

Deploy the Share Worker and a new saved Website version. Verify:

```bash
curl -fsS https://share.cinebar.cc/updates/latest.json
curl -fsS https://cinebar.cc/appcast.xml | xmllint --noout -
```

Expected: Build 16 sees the GitHub Releases migration link and Sparkle clients
receive valid XML.

- [ ] **Step 8: Commit**

```bash
git add CineBar/Tools/publish_sparkle_update.sh \
  CineBarWebsite/public/appcast.xml \
  CineBarShare/worker.js \
  CineBarShare/tests/share-worker.test.mjs
git commit -m "feat: publish signed CineBar update feed"
```

### Task 4: Prove a Real Old-to-New Update

**Files:**
- Modify: `CineBar/README.md`
- Modify: `CineBar/请先阅读-测试版安装说明.html`
- Modify: `CineBar/请先阅读-测试版安装说明.txt`

**Interfaces:**
- Consumes: an installed Sparkle-enabled older Build, a signed newer Build, and the live appcast.
- Produces: a verified release candidate and accurate installation/update documentation.

- [ ] **Step 1: Install the lower Sparkle-enabled Build**

Move the lower Build into `/Applications`, launch it once, and confirm its
`CFBundleVersion` is lower than the appcast build.

- [ ] **Step 2: Verify the update dialog**

In Settings → 检查更新, click “立即检查”.

Expected: Sparkle displays the exact version, date, and release notes from the
appcast. The current CineBar window remains usable until the user confirms.

- [ ] **Step 3: Verify cancellation**

Cancel the update.

Expected: the old app continues to run and its bundle remains intact.

- [ ] **Step 4: Verify tamper rejection**

Host a test appcast pointing to a copy of the ZIP with one changed byte while
retaining the original signature.

Expected: Sparkle rejects the archive and does not replace CineBar.app.

- [ ] **Step 5: Verify successful installation and relaunch**

Restore the valid appcast, check again, choose installation, and allow CineBar
to relaunch.

Expected:

- the app relaunches automatically;
- `CFBundleVersion` matches the new build;
- menu-bar icon, movie/TV browsing, ratings, share links, and reminders still
  work;
- no password is requested unless macOS permissions for the installation
  location require authorization.

- [ ] **Step 6: Update documentation**

Document:

- Build 16 requires one manual migration through GitHub Releases;
- subsequent versions update inside CineBar;
- updates are verified with CineBar's EdDSA key;
- the build is still not Apple-notarized;
- users can disable automatic checks in Settings.

- [ ] **Step 7: Run the full release gate**

Run:

```bash
node --test CineBarShare/tests/share-worker.test.mjs
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
CineBar/Tools/build_test_package.sh
verification_dir=$(mktemp -d "${TMPDIR:-/tmp}/cinebar-verify.XXXXXX")
ditto -x -k dist/CineBar-0.8.3-test-build-17-universal.zip "$verification_dir"
packaged_app=$(find "$verification_dir" -name CineBar.app -type d -maxdepth 3 -print -quit)
test -n "$packaged_app"
codesign --verify --deep --strict "$packaged_app"
```

Expected: every automated check passes.

- [ ] **Step 8: Commit**

```bash
git add CineBar/README.md \
  CineBar/请先阅读-测试版安装说明.html \
  CineBar/请先阅读-测试版安装说明.txt
git commit -m "docs: explain secure CineBar updates"
```
