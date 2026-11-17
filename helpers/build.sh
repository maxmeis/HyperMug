#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./helpers/check-layers.sh
. helpers/swift-env.sh

RELEASE="${REQUIRE_SIGNING:-0}"
VARIANT="${APP_VARIANT:-dev}"
BUILD_ROOT="${BUILD_ROOT:-build}"
if [ "$RELEASE" = 1 ]; then VARIANT=production; fi
case "$VARIANT" in
  dev)
    APP="$BUILD_ROOT/HyperMug Dev.app"
    CORE="$BUILD_ROOT/core-dev"
    APP_NAME="HyperMug Dev"
    BUNDLE_ID=com.maxmeis.hypermug.dev
    SWIFT_BASE_FLAGS+=(-D HYPERMUG_DEV)
    ;;
  production)
    APP="$BUILD_ROOT/HyperMug.app"
    CORE="$BUILD_ROOT/core"
    APP_NAME=HyperMug
    BUNDLE_ID=com.maxmeis.hypermug
    ;;
  *) echo "error: APP_VARIANT must be dev or production" >&2; exit 1;;
esac
VERSION="${APP_VERSION:-0.1.0}"
NUMBER="${BUILD_NUMBER:-1}"
CHANNEL_META="${RELEASE_CHANNEL:-local}"
if [ "$VARIANT" = dev ]; then CHANNEL_META=local; fi
case "$CHANNEL_META" in local|production) ;; *) echo "error: invalid RELEASE_CHANNEL" >&2; exit 1;; esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: invalid APP_VERSION" >&2; exit 1; }
[[ "$NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "error: invalid BUILD_NUMBER" >&2; exit 1; }
if [ "$RELEASE" = 1 ]; then
  [ "$VARIANT" = production ] && [ "$CHANNEL_META" = production ] || { echo "error: release requires production variant" >&2; exit 1; }
  [[ "${SIGN_ID:-}" == Developer\ ID\ Application:* ]] || { echo "error: release requires SIGN_ID=Developer ID Application: ..." >&2; exit 1; }
  security find-identity -v -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} | grep -Fq "\"$SIGN_ID\"" || { echo "error: Developer ID identity unavailable" >&2; exit 1; }
fi
SIGN_ID="${SIGN_ID:--}"
if [ "$SIGN_ID" != - ] && ! security find-identity -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} | grep -Fq "\"$SIGN_ID\""; then
  echo "error: signing identity $SIGN_ID not found." >&2
  exit 1
fi
rm -rf "$APP" "$CORE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp Source/Branding/HyperMug.icns "$APP/Contents/Resources/HyperMug.icns"
compile_core_module "$CORE"
# Generate the editor schema from the exact same model/variant as the app, before signing.
swiftc -O -parse-as-library "${SWIFT_BASE_FLAGS[@]}" -I "$CORE" \
  helpers/schema-main.swift "$CORE/HyperMugCore.o" -o "$CORE/render-schema"
"$CORE/render-schema" "$APP/Contents/Resources"
swiftc -O -parse-as-library "${SWIFT_BASE_FLAGS[@]}" -module-name HyperMug \
  -I "$CORE" Source/HyperMug/Sources/Platform/*.swift Source/HyperMug/Sources/App/*.swift "$CORE/HyperMugCore.o" \
  -o "$APP/Contents/MacOS/HyperMug" -framework IOKit -framework Carbon
cp Source/HyperMug/Info.plist "$APP/Contents/"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :HyperMugReleaseChannel $CHANNEL_META" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$PLIST"
SIGN_OPTIONS=(--force --sign "$SIGN_ID")
if [ "$RELEASE" = 1 ]; then SIGN_OPTIONS+=(--options runtime --timestamp); fi
if [ -n "${SIGN_KEYCHAIN:-}" ]; then SIGN_OPTIONS+=(--keychain "$SIGN_KEYCHAIN"); fi
codesign "${SIGN_OPTIONS[@]}" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built: $APP"
