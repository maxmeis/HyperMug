#!/usr/bin/env bash
# Check a production bundle's updater: feed keys, framework symlinks, and every
# nested Sparkle component signed by the release team with hardened runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?app}"; team="${2:?Apple team}"
plist="$app/Contents/Info.plist"
value() { plutil -extract "$1" raw -o - "$plist"; }
[[ "$(value SUFeedURL)" == https://raw.githubusercontent.com/maxmeis/hypermug/updates/appcast.xml ]] || { echo 'Unexpected SUFeedURL' >&2; exit 1; }
[[ "$(value SUPublicEDKey)" == "$(plutil -extract SUPublicEDKey raw -o - Source/HyperMug/Info.plist)" ]] || { echo 'SUPublicEDKey differs from the source template' >&2; exit 1; }
[[ "$(value SUEnableAutomaticChecks)" == true && "$(value SUVerifyUpdateBeforeExtraction)" == true ]] || { echo 'Sparkle checks are not enabled' >&2; exit 1; }
[[ "$(value SUScheduledCheckInterval)" == 86400 ]] || { echo 'Sparkle must check daily' >&2; exit 1; }
framework="$app/Contents/Frameworks/Sparkle.framework"
for link in Versions/Current Sparkle Resources XPCServices Autoupdate Updater.app; do
  test -L "$framework/$link" || { echo "Sparkle.framework/$link is not a symlink" >&2; exit 1; }
done
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
version="$framework/Versions/B"
for code in "$version/XPCServices/Installer.xpc" "$version/XPCServices/Downloader.xpc" "$version/Autoupdate" "$version/Updater.app" "$framework"; do
  codesign -dv --verbose=4 "$code" 2> "$work/signature.txt"
  grep -Fqx "TeamIdentifier=$team" "$work/signature.txt" || { echo "Unexpected signing team: $code" >&2; exit 1; }
  grep -Eq 'flags=.*\(runtime\)' "$work/signature.txt" || { echo "Missing hardened runtime: $code" >&2; exit 1; }
  grep -Eq '^Timestamp=' "$work/signature.txt" || { echo "Missing secure timestamp: $code" >&2; exit 1; }
done
