#!/bin/bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "Usage: $0 ARCHIVE DOWNLOAD_URL VERSION BUILD PUBLISHED_AT RELEASE_NOTES_FILE" >&2
  exit 64
fi

archive=$1
download_url=$2
version=$3
build=$4
published_at=$5
release_notes_file=$6

[[ -f "$archive" ]] || {
  echo "Archive does not exist: $archive" >&2
  exit 66
}
[[ -f "$release_notes_file" ]] || {
  echo "Release notes file does not exist: $release_notes_file" >&2
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
[[ "$published_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
  echo "Publication date must use YYYY-MM-DD" >&2
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

format_rfc822_date() {
  local formatted
  if formatted=$(LC_ALL=C date -j -u -f '%Y-%m-%d' "$published_at" \
    '+%Y-%m-%d|%a, %d %b %Y 00:00:00 +0000' 2>/dev/null); then
    :
  elif formatted=$(LC_ALL=C date -u -d "$published_at 00:00:00" \
    '+%Y-%m-%d|%a, %d %b %Y 00:00:00 +0000' 2>/dev/null); then
    :
  else
    return 1
  fi

  [[ "${formatted%%|*}" == "$published_at" ]] || return 1
  printf '%s' "${formatted#*|}"
}

rfc822_published_at=$(format_rfc822_date) || {
  echo "Publication date is not a valid calendar date" >&2
  exit 65
}

if [[ -f "$output" ]] && xmllint --noout "$output" 2>/dev/null; then
  existing_build=$(xmllint --xpath \
    'string(//*[local-name()="enclosure"]/@*[local-name()="version"])' \
    "$output")
  if [[ "$existing_build" =~ ^[1-9][0-9]*$ ]] &&
    (( build <= existing_build )); then
    echo "Build must be greater than existing appcast Build $existing_build" >&2
    exit 65
  fi
fi

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\\&apos;/g"
}

description_text_escape() {
  printf '%s' "$1" | xml_escape | xml_escape
}

release_notes_count=0
while IFS= read -r release_note || [[ -n "$release_note" ]]; do
  release_note=${release_note%$'\r'}
  if [[ "$release_note" =~ [^[:space:]] ]]; then
    ((release_notes_count += 1))
  fi
done < "$release_notes_file"
[[ "$release_notes_count" -gt 0 ]] || {
  echo "Release notes file must contain at least one non-empty line" >&2
  exit 65
}

escaped_download_url=$(printf '%s' "$download_url" | xml_escape)
escaped_version=$(printf '%s' "$version" | xml_escape)

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
  printf '%s' '      <description>&lt;ul&gt;'
  while IFS= read -r release_note || [[ -n "$release_note" ]]; do
    release_note=${release_note%$'\r'}
    [[ "$release_note" =~ [^[:space:]] ]] || continue
    escaped_release_note=$(description_text_escape "$release_note")
    printf '&lt;li&gt;%s&lt;/li&gt;' "$escaped_release_note"
  done < "$release_notes_file"
  printf '%s\n' '&lt;/ul&gt;</description>'
  printf '      <pubDate>%s</pubDate>\n' "$rfc822_published_at"
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
