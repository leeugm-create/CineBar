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
archive_temp=""
extract_temp=""
previous_destination=""

cleanup() {
  if [[ -n "$archive_temp" && -f "$archive_temp" ]]; then
    rm -f "$archive_temp"
  fi
  if [[ -n "$extract_temp" && -d "$extract_temp" ]]; then
    rm -rf "$extract_temp"
  fi
  if [[ -n "$previous_destination" && -d "$previous_destination" ]]; then
    if [[ ! -e "$destination" ]]; then
      mv "$previous_destination" "$destination"
    else
      rm -rf "$previous_destination"
    fi
  fi
}
trap cleanup EXIT

mkdir -p "$vendor_root"

archive_sha=""
if [[ -f "$archive" ]]; then
  archive_sha=$(shasum -a 256 "$archive" | awk '{print $1}')
fi

if [[ "$archive_sha" != "$expected_sha" ]]; then
  archive_temp=$(mktemp "$vendor_root/.Sparkle-$version.archive.XXXXXX")
  curl --fail --location --proto '=https' --tlsv1.2 \
    "$url" --output "$archive_temp"
  downloaded_sha=$(shasum -a 256 "$archive_temp" | awk '{print $1}')
  [[ "$downloaded_sha" == "$expected_sha" ]] || {
    echo "Sparkle checksum mismatch" >&2
    exit 1
  }
  mv -f "$archive_temp" "$archive"
  archive_temp=""
fi

verified_sha=$(shasum -a 256 "$archive" | awk '{print $1}')
[[ "$verified_sha" == "$expected_sha" ]] || {
  echo "Sparkle checksum mismatch" >&2
  exit 1
}

extract_temp=$(mktemp -d "$vendor_root/.Sparkle-$version.extract.XXXXXX")
tar -xJf "$archive" -C "$extract_temp" --strip-components=1
xattr -cr "$extract_temp"
test -d "$extract_temp/Sparkle.framework"
test -x "$extract_temp/bin/sign_update"
codesign --verify --deep --strict "$extract_temp/Sparkle.framework"

if [[ -e "$destination" ]]; then
  previous_destination=$(mktemp -d \
    "$vendor_root/.Sparkle-$version.previous.XXXXXX")
  rmdir "$previous_destination"
  mv "$destination" "$previous_destination"
fi

mv "$extract_temp" "$destination"
extract_temp=""

if [[ -n "$previous_destination" ]]; then
  rm -rf "$previous_destination"
  previous_destination=""
fi
