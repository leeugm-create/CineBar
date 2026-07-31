#!/bin/bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 ARCHIVE DOWNLOAD_URL VERSION BUILD PUBLISHED_AT" >&2
  exit 64
fi

archive=$1
download_url=$2
version=$3
build=$4
published_at=$5

[[ -f "$archive" ]] || {
  echo "Archive does not exist: $archive" >&2
  exit 66
}
[[ "$download_url" == https://* ]] || {
  echo "Download URL must use HTTPS" >&2
  exit 65
}
[[ "$build" =~ ^[1-9][0-9]*$ ]] || {
  echo "Build must be a positive integer" >&2
  exit 65
}

script_dir=$(cd "$(dirname "$0")" && pwd)
app_dir=$(cd "$script_dir/.." && pwd)
repo_root=$(cd "$app_dir/.." && pwd)
sign_update="$app_dir/.vendor/Sparkle-2.9.2/bin/sign_update"
output="$repo_root/CineBarWebsite/public/appcast.xml"
output_dir=$(dirname "$output")

[[ -x "$sign_update" ]] || {
  echo "Sparkle sign_update is unavailable" >&2
  exit 69
}

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\\&apos;/g"
}

escaped_download_url=$(printf '%s' "$download_url" | xml_escape)
escaped_version=$(printf '%s' "$version" | xml_escape)
escaped_published_at=$(printf '%s' "$published_at" | xml_escape)

signature_output=$("$sign_update" "$archive")
ed_signature=$(printf '%s\n' "$signature_output" |
  sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -n 1)
archive_length=$(printf '%s\n' "$signature_output" |
  sed -n 's/.*length="\([0-9][0-9]*\)".*/\1/p' | head -n 1)

[[ -n "$ed_signature" ]] || {
  echo "Sparkle signer returned no EdDSA signature" >&2
  exit 70
}
[[ "$archive_length" =~ ^[1-9][0-9]*$ ]] || {
  echo "Sparkle signer returned an invalid archive length" >&2
  exit 70
}

escaped_ed_signature=$(printf '%s' "$ed_signature" | xml_escape)
mkdir -p "$output_dir"
temporary_output=$(mktemp "$output_dir/.appcast.xml.XXXXXX")
cleanup() {
  rm -f "$temporary_output"
}
trap cleanup EXIT

{
  printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>'
  printf '%s\n' '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
  printf '%s\n' '  <channel>'
  printf '%s\n' '    <title>CineBar Updates</title>'
  printf '%s\n' '    <link>https://cinebar.cc/appcast.xml</link>'
  printf '%s\n' '    <description>CineBar signed application updates</description>'
  printf '    <item>\n'
  printf '      <title>CineBar %s</title>\n' "$escaped_version"
  printf '      <pubDate>%s</pubDate>\n' "$escaped_published_at"
  printf '%s\n' '      <enclosure'
  printf '        url="%s"\n' "$escaped_download_url"
  printf '        sparkle:version="%s"\n' "$build"
  printf '        sparkle:shortVersionString="%s"\n' "$escaped_version"
  printf '        length="%s"\n' "$archive_length"
  printf '%s\n' '        type="application/octet-stream"'
  printf '        sparkle:edSignature="%s"/>\n' "$escaped_ed_signature"
  printf '%s\n' '    </item>'
  printf '%s\n' '  </channel>'
  printf '%s\n' '</rss>'
} > "$temporary_output"

xmllint --noout "$temporary_output"
chmod 644 "$temporary_output"
mv -f "$temporary_output" "$output"
trap - EXIT

echo "Published signed appcast to $output"
