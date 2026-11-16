#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CHANNEL:?}" "${VERSION:?}" "${BUILD_NUMBER:?}" "${SOURCE_REPOSITORY:?}" "${RELEASES_REPOSITORY:?}" "${TAP_REPOSITORY:?}" "${GITHUB_ACTOR:?}" "${GITHUB_TRIGGERING_ACTOR:?}" "${GITHUB_REF:?}" "${GITHUB_SHA:?}"
args=(--channel "$CHANNEL" --version "$VERSION" --actor "$GITHUB_ACTOR" --triggering-actor "$GITHUB_TRIGGERING_ACTOR" --ref "$GITHUB_REF" --sha "$GITHUB_SHA" --source-repo "$SOURCE_REPOSITORY" --releases-repo "$RELEASES_REPOSITORY" --tap-repo "$TAP_REPOSITORY")
python3 scripts/release_metadata.py validate "${args[@]}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo 'Invalid build number' >&2; exit 1; }
: "${DEVELOPER_ID_P12_BASE64:?}" "${DEVELOPER_ID_P12_PASSWORD:?}" "${SIGN_ID:?}" "${SPARKLE_EDDSA_PRIVATE_KEY:?}"
source scripts/notary_auth.sh
umask 077
work="$(mktemp -d)"
keychain="$work/release.keychain-db"
original_keychains=()
search_list_changed=0
cleanup() {
  if [[ "$search_list_changed" == 1 ]]; then
    security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1 || true
  fi
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
configure_notary_auth "$work"
keychain_list="$(security list-keychains -d user)"
while IFS= read -r existing_keychain; do
  if [[ -n "$existing_keychain" ]]; then original_keychains+=("$existing_keychain"); fi
done < <(printf '%s' "$keychain_list" | python3 -c 'import shlex, sys; print("\n".join(shlex.split(sys.stdin.read())))')
umask 077
printf '%s' "$DEVELOPER_ID_P12_BASE64" | base64 -D > "$work/identity.p12"
security create-keychain -p "$RUNNER_TEMP" "$keychain"
security unlock-keychain -p "$RUNNER_TEMP" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security import "$work/identity.p12" -k "$keychain" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$RUNNER_TEMP" "$keychain"
security list-keychains -d user -s "$keychain" "${original_keychains[@]}"
search_list_changed=1
security find-identity -v -p codesigning "$keychain" | grep -F "$SIGN_ID"
app_version="$VERSION"
if [[ "$CHANNEL" == beta ]]; then app_version="0.0.${VERSION##*.}"; fi
export SIGN_KEYCHAIN="$keychain" REQUIRE_SIGNING=1 APP_VERSION="$app_version" UPDATE_CHANNEL="$CHANNEL"
export APPCAST_URL="https://raw.githubusercontent.com/${RELEASES_REPOSITORY}/updates/appcast-${CHANNEL}.xml"
export SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:?}"
./build.sh
codesign --verify --deep --strict --verbose=2 build/HyperMug.app
ditto -c -k --keepParent build/HyperMug.app "$work/notary.zip"
submit_for_notarization "$work/notary.zip"
xcrun stapler staple build/HyperMug.app
xcrun stapler validate build/HyperMug.app
mkdir -p build/release
archive="build/release/HyperMug-${VERSION}.zip"
ditto -c -k --keepParent build/HyperMug.app "$archive"
# Sparkle's sign_update accepts a private EdDSA key file via --ed-key-file.
printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" > "$work/eddsa.key"
source scripts/sparkle.sh
signature="$("${SPARKLE_ROOT:?}/bin/sign_update" "$archive" --ed-key-file "$work/eddsa.key")"
signature="$(printf '%s' "$signature" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
[[ -n "$signature" ]] || { echo 'Sparkle signature missing' >&2; exit 1; }
swift scripts/verify-update.swift "$archive" "$signature"
python3 scripts/release_metadata.py render "${args[@]}" --build-number "$BUILD_NUMBER" --zip "$archive" --signature "$signature" --output build/release
