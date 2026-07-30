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
  xattr -cr "$destination"
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
xattr -cr "$destination"
test -d "$destination/Sparkle.framework"
test -x "$destination/bin/sign_update"
