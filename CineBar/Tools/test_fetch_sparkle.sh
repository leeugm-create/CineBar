#!/bin/bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
app_dir=$(cd "$script_dir/.." && pwd)
destination="$app_dir/.vendor/Sparkle-2.9.2"
target="$destination/Sparkle.framework/Versions/B/Resources/Info.plist"
backup_dir=$(mktemp -d "${TMPDIR:-/tmp}/cinebar-sparkle-test.XXXXXX")
completed=0

cleanup() {
  if [[ "$completed" -ne 1 && -f "$backup_dir/Info.plist" ]]; then
    cp "$backup_dir/Info.plist" "$target"
    xattr -cr "$destination"
  fi
  rm -rf "$backup_dir"
}
trap cleanup EXIT

"$script_dir/fetch_sparkle.sh"
cp "$target" "$backup_dir/Info.plist"
original_sha=$(shasum -a 256 "$target" | awk '{print $1}')

printf '\nCineBar cache tamper regression\n' >> "$target"
tampered_sha=$(shasum -a 256 "$target" | awk '{print $1}')
[[ "$tampered_sha" != "$original_sha" ]]

"$script_dir/fetch_sparkle.sh"
restored_sha=$(shasum -a 256 "$target" | awk '{print $1}')
[[ "$restored_sha" == "$original_sha" ]]
codesign --verify --deep --strict "$destination/Sparkle.framework"

completed=1
echo "Sparkle cache restoration regression passed"
