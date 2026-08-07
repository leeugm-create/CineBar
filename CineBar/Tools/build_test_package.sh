#!/bin/bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
app_source_dir=$(cd "$script_dir/.." && pwd)
repo_root=$(cd "$app_source_dir/.." && pwd)
source_dir="$app_source_dir/Sources/CineBar"
swift_sources=("$source_dir"/*.swift)
info_plist="$app_source_dir/Info.plist"
version=$(/usr/libexec/PlistBuddy \
  -c "Print :CFBundleShortVersionString" "$info_plist")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist")
build_manifest=$("$script_dir/check_build_provenance.sh" \
  "$repo_root" "$version" "$build" \
  CineBar/Sources/CineBar \
  CineBar/Info.plist \
  CineBar/PkgInfo \
  CineBar/Assets \
  CineBar/ReleaseNotes \
  CineBar/INSTALL.md \
  CineBar/README.md \
  CineBar/请先阅读-测试版安装说明.html \
  CineBar/请先阅读-测试版安装说明.txt \
  CineBar/Tools/build_test_package.sh \
  CineBar/Tools/check_build_provenance.sh)
"$script_dir/fetch_sparkle.sh"
sparkle_dir="$app_source_dir/.vendor/Sparkle-2.9.2"
package_name="CineBar-$version-test-build-$build"
dist_dir="$repo_root/dist"
output_zip="$dist_dir/$package_name-universal.zip"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/cinebar-test-build.XXXXXX")

cleanup() {
  rm -rf "$build_dir"
}
trap cleanup EXIT

arm_binary="$build_dir/CineBar-arm64"
intel_binary="$build_dir/CineBar-x86_64"
delivery_dir="$build_dir/$package_name"
app_bundle="$delivery_dir/CineBar.app"
contents_dir="$app_bundle/Contents"

echo "Compiling CineBar for Apple silicon…"
xcrun swiftc \
  -parse-as-library \
  -O \
  -target arm64-apple-macosx13.0 \
  -F "$sparkle_dir" \
  -framework Sparkle \
  -framework EventKit \
  -framework AVFoundation \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Frameworks \
  "${swift_sources[@]}" \
  -o "$arm_binary"

echo "Compiling CineBar for Intel Macs…"
xcrun swiftc \
  -parse-as-library \
  -O \
  -target x86_64-apple-macosx13.0 \
  -F "$sparkle_dir" \
  -framework Sparkle \
  -framework EventKit \
  -framework AVFoundation \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Frameworks \
  "${swift_sources[@]}" \
  -o "$intel_binary"

mkdir -p \
  "$contents_dir/MacOS" \
  "$contents_dir/Resources" \
  "$contents_dir/Frameworks"
lipo -create "$arm_binary" "$intel_binary" \
  -output "$contents_dir/MacOS/CineBar"
chmod 755 "$contents_dir/MacOS/CineBar"

cp "$info_plist" "$contents_dir/Info.plist"
cp "$app_source_dir/PkgInfo" "$contents_dir/PkgInfo"
printf '%s\n' "$build_manifest" \
  > "$contents_dir/Resources/BuildManifest.json"
printf '%s\n' "$build_manifest" > "$delivery_dir/BuildManifest.json"
cp "$app_source_dir/Assets/CineBar.icns" \
  "$contents_dir/Resources/CineBar.icns"
cp "$app_source_dir/Assets/MenuBarIcon-template.png" \
  "$contents_dir/Resources/MenuBarIcon-template.png"
for donation_image in wxpay alipay; do
  if [[ -f "$app_source_dir/Assets/$donation_image.png" ]]; then
    cp "$app_source_dir/Assets/$donation_image.png" \
      "$contents_dir/Resources/$donation_image.png"
  fi
done
ditto "$sparkle_dir/Sparkle.framework" \
  "$contents_dir/Frameworks/Sparkle.framework"
xattr -cr "$contents_dir/Frameworks/Sparkle.framework"

for localization in "$app_source_dir"/Assets/Localization/*.lproj; do
  destination="$contents_dir/Resources/$(basename "$localization")"
  mkdir -p "$destination"
  cp "$localization/Localizable.strings" \
    "$destination/Localizable.strings"
done

sparkle_framework="$contents_dir/Frameworks/Sparkle.framework"
for xpc_service in \
  "$sparkle_framework"/Versions/Current/XPCServices/*.xpc; do
  codesign --force --sign - "$xpc_service"
done
codesign --force --sign - \
  "$sparkle_framework/Versions/Current/Updater.app"
codesign --force --sign - "$sparkle_framework"
codesign --force --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"

cp "$app_source_dir/INSTALL.md" "$delivery_dir/"
cp "$app_source_dir/请先阅读-测试版安装说明.html" "$delivery_dir/"
cp "$app_source_dir/请先阅读-测试版安装说明.txt" "$delivery_dir/"
if [[ -d "$app_source_dir/ReleaseNotes" ]]; then
  cp -R "$app_source_dir/ReleaseNotes" "$delivery_dir/"
  cp -R "$app_source_dir/ReleaseNotes" "$contents_dir/Resources/ReleaseNotes"
fi

mkdir -p "$dist_dir"
rm -f "$output_zip"
ditto -c -k --sequesterRsrc --keepParent "$delivery_dir" "$output_zip"

echo "Created $output_zip"
