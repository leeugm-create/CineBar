#!/bin/bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
app_source_dir=$(cd "$script_dir/.." && pwd)
repo_root=$(cd "$app_source_dir/.." && pwd)
source_file="$app_source_dir/Sources/CineBar/main.swift"
info_plist="$app_source_dir/Info.plist"
package_name="CineBar-0.8.2-test.1"
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
  "$source_file" \
  -o "$arm_binary"

echo "Compiling CineBar for Intel Macs…"
xcrun swiftc \
  -parse-as-library \
  -O \
  -target x86_64-apple-macosx13.0 \
  "$source_file" \
  -o "$intel_binary"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
lipo -create "$arm_binary" "$intel_binary" \
  -output "$contents_dir/MacOS/CineBar"
chmod 755 "$contents_dir/MacOS/CineBar"

cp "$info_plist" "$contents_dir/Info.plist"
cp "$app_source_dir/PkgInfo" "$contents_dir/PkgInfo"
cp "$app_source_dir/Assets/CineBar.icns" \
  "$contents_dir/Resources/CineBar.icns"
cp "$app_source_dir/Assets/MenuBarIcon-template.png" \
  "$contents_dir/Resources/MenuBarIcon-template.png"

for localization in "$app_source_dir"/Assets/Localization/*.lproj; do
  destination="$contents_dir/Resources/$(basename "$localization")"
  mkdir -p "$destination"
  cp "$localization/Localizable.strings" \
    "$destination/Localizable.strings"
done

codesign --force --deep --sign - "$app_bundle"

cp "$app_source_dir/请先阅读-测试版安装说明.html" "$delivery_dir/"
cp "$app_source_dir/请先阅读-测试版安装说明.txt" "$delivery_dir/"

mkdir -p "$dist_dir"
rm -f "$output_zip"
ditto -c -k --sequesterRsrc --keepParent "$delivery_dir" "$output_zip"

echo "Created $output_zip"
