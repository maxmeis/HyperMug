#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
automation_root="$PWD"
source_root="${RELEASE_SOURCE_DIR:-$PWD}"
[[ -d "$source_root" ]] || { echo "Release source checkout missing" >&2; exit 1; }
source_root="$(cd "$source_root" && pwd)"
app="$source_root/build/HyperMug.app"
: "${CHANNEL:?}" "${VERSION:?}" "${BUILD_NUMBER:?}" "${SOURCE_REPOSITORY:?}" "${RELEASES_REPOSITORY:?}" "${TAP_REPOSITORY:?}" "${GITHUB_ACTOR:?}" "${GITHUB_TRIGGERING_ACTOR:?}" "${GITHUB_REF:?}" "${GITHUB_SHA:?}"
args=(--channel "$CHANNEL" --version "$VERSION" --actor "$GITHUB_ACTOR" --triggering-actor "$GITHUB_TRIGGERING_ACTOR" --ref "$GITHUB_REF" --sha "$GITHUB_SHA" --source-repo "$SOURCE_REPOSITORY" --releases-repo "$RELEASES_REPOSITORY" --tap-repo "$TAP_REPOSITORY")
python3 helpers/release_metadata.py validate "${args[@]}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo 'Invalid build number' >&2; exit 1; }
: "${SIGN_KEYCHAIN:?}" "${RELEASE_BOT_SIGNING_SCRIPT:?}" "${RELEASE_BOT_SIGN_ID:?}" "${RELEASE_BOT_NOTARY_PROFILE:?}" "${SPARKLE_EDDSA_PRIVATE_KEY:?}"
[[ -f "$RELEASE_BOT_SIGNING_SCRIPT" ]] || { echo 'Shared signing script missing' >&2; exit 1; }
umask 077
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
identity="$(python3 - "$CHANNEL" "$VERSION" <<'PY'
import sys
from helpers.release_metadata import bundle_identity
print(*bundle_identity(sys.argv[1], sys.argv[2]))
PY
)"
read -r app_version expected_build <<< "$identity"
[[ "$BUILD_NUMBER" == "$expected_build" ]] || { echo 'Build number does not match release tag' >&2; exit 1; }

export REQUIRE_SIGNING=1 APP_VERSION="$app_version" RELEASE_CHANNEL="$CHANNEL"
export APPCAST_URL="https://raw.githubusercontent.com/${RELEASES_REPOSITORY}/updates/appcast-${CHANNEL}.xml"
export SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:?}"
make -C "$source_root" build
python3 helpers/check-bundle-schema.py "$app"
bundle_plist="$app"/Contents/Info.plist
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$bundle_plist")" == "$app_version" ]] || { echo 'Built marketing version mismatch' >&2; exit 1; }
[[ "$(plutil -extract CFBundleVersion raw -o - "$bundle_plist")" == "$BUILD_NUMBER" ]] || { echo 'Built build version mismatch' >&2; exit 1; }
[[ "$(plutil -extract HyperMugReleaseChannel raw -o - "$bundle_plist")" == "$CHANNEL" ]] || { echo 'Built channel mismatch' >&2; exit 1; }
bash "$RELEASE_BOT_SIGNING_SCRIPT" sign-app "$app"
bash "$RELEASE_BOT_SIGNING_SCRIPT" notarize-app "$app"
mkdir -p build/release
archive="build/release/HyperMug-${VERSION}.zip"
ditto -c -k --keepParent "$app" "$archive"
# Sparkle's sign_update accepts a private EdDSA key file via --ed-key-file.
printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" > "$work/eddsa.key"
SPARKLE_ROOT="$(cd "$source_root" && source helpers/sparkle.sh && printf '%s' "$SPARKLE_ROOT")"
signature="$("${SPARKLE_ROOT:?}/bin/sign_update" "$archive" --ed-key-file "$work/eddsa.key")"
signature="$(printf '%s' "$signature" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
[[ -n "$signature" ]] || { echo 'Sparkle signature missing' >&2; exit 1; }
swift helpers/verify-update.swift "$archive" "$signature"
python3 helpers/release_metadata.py render "${args[@]}" --build-number "$BUILD_NUMBER" --zip "$archive" --signature "$signature" --output build/release
