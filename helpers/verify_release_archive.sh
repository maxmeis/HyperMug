#!/usr/bin/env bash
# Verify the downloaded bytes that Homebrew will install.
set -euo pipefail
cd "$(dirname "$0")/.."
archive="${1:?archive}"; version="${2:?version}"; team="${3:?Apple team}"
[[ "$archive" = /* ]] || archive="$PWD/$archive"
test -s "$archive"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ditto -x -k "$archive" "$work"
app="$work/HyperMug.app"
test -d "$app"
plist="$app/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" == "$version" ]]
[[ "$(plutil -extract CFBundleVersion raw -o - "$plist")" == "$version" ]]
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$plist")" == com.maxmeis.hypermug ]]
python3 helpers/check-bundle-schema.py "$app"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dv --verbose=4 "$app" 2> "$work/signature.txt"
grep -Fqx "TeamIdentifier=$team" "$work/signature.txt"
grep -Eq 'flags=.*\(runtime\)' "$work/signature.txt"
grep -Eq '^Timestamp=' "$work/signature.txt"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app"
