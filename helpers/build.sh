#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./helpers/check-layers.sh
. helpers/swift-env.sh
. helpers/sparkle.sh
sparkle_prepare

RELEASE="${REQUIRE_SIGNING:-0}"
VARIANT="${APP_VARIANT:-dev}"
if [ "$RELEASE" = 1 ]; then VARIANT=production; fi
case "$VARIANT" in
  dev)
    APP="build/HyperMug Dev.app"
    CORE=build/core-dev
    APP_NAME="HyperMug Dev"
    BUNDLE_ID=com.maxmeis.hypermug.dev
    SWIFT_BASE_FLAGS+=(-D HYPERMUG_DEV)
    ;;
  production)
    APP=build/HyperMug.app
    CORE=build/core
    APP_NAME=HyperMug
    BUNDLE_ID=com.maxmeis.hypermug
    ;;
  *) echo "error: APP_VARIANT must be dev or production" >&2; exit 1;;
esac
VERSION="${APP_VERSION:-0.1.0}"
NUMBER="${BUILD_NUMBER:-1}"
CHANNEL_META="${RELEASE_CHANNEL:-local}"
REPOSITORY="${RELEASES_REPOSITORY:-maxmeis/HyperMug}"
FEED="${APPCAST_URL:-https://raw.githubusercontent.com/${REPOSITORY}/updates/appcast-stable.xml}"
KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
if [ "$VARIANT" = dev ]; then KEY=""; CHANNEL_META=local; fi
case "$CHANNEL_META" in local|stable|canary) ;; *) echo "error: invalid RELEASE_CHANNEL" >&2; exit 1;; esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: invalid APP_VERSION" >&2; exit 1; }
[[ "$NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "error: invalid BUILD_NUMBER" >&2; exit 1; }
if [ -n "$KEY" ] || [ "$RELEASE" = 1 ]; then
  KEY_BYTES="$(printf '%s' "$KEY" | base64 -D 2>/dev/null | wc -c | tr -d ' ' || true)"
  [[ "$KEY" =~ ^[A-Za-z0-9+/]{43}=$ && "$KEY_BYTES" = 32 ]] || { echo "error: SPARKLE_PUBLIC_ED_KEY must be a 32-byte base64 Ed25519 key" >&2; exit 1; }
  python3 - "$FEED" <<'PY'
import sys, urllib.parse
u = urllib.parse.urlsplit(sys.argv[1])
if u.scheme != 'https' or not u.hostname or u.username or u.password or any(c.isspace() for c in sys.argv[1]):
    sys.exit('error: APPCAST_URL must be a valid HTTPS URL')
PY
fi
if [ "$RELEASE" = 1 ]; then
  [[ "${SIGN_ID:-}" == Developer\ ID\ Application:* ]] || { echo "error: release requires SIGN_ID=Developer ID Application: ..." >&2; exit 1; }
  security find-identity -v -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} | grep -Fq "\"$SIGN_ID\"" || { echo "error: Developer ID identity unavailable" >&2; exit 1; }
fi
SIGN_ID="${SIGN_ID:-HyperMug Local Signing}"
if [ "$SIGN_ID" = - ]; then
  [ "${ALLOW_ADHOC_SIGNING:-0}" = 1 ] || { echo "error: ad-hoc signing resets input permissions. Use a signing identity, or explicitly set ALLOW_ADHOC_SIGNING=1 for a disposable build." >&2; exit 1; }
elif ! security find-identity -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} | grep -Fq "\"$SIGN_ID\""; then
  echo "error: signing identity $SIGN_ID not found. Run make signing once, then rebuild." >&2
  exit 1
fi
rm -rf "$APP" "$CORE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp Source/Branding/HyperMug.icns "$APP/Contents/Resources/HyperMug.icns"
compile_core_module "$CORE"
swiftc -O -parse-as-library "${SWIFT_BASE_FLAGS[@]}" -module-name HyperMug \
  -I "$CORE" -F "$SPARKLE_FRAMEWORK_DIR" Source/HyperMug/Sources/Platform/*.swift Source/HyperMug/Sources/App/*.swift "$CORE/HyperMugCore.o" \
  -o "$APP/Contents/MacOS/HyperMug" -framework IOKit -framework Carbon -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks
cp -R "$SPARKLE_FRAMEWORK_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
cp Source/HyperMug/Info.plist "$APP/Contents/"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :HyperMugReleaseChannel $CHANNEL_META" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$PLIST"
if [ -n "$KEY" ]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $FEED" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $KEY" "$PLIST"
else
  echo "warning: updates disabled; set SPARKLE_PUBLIC_ED_KEY and APPCAST_URL to enable."
fi
SIGN_OPTIONS=(--force --sign "$SIGN_ID")
if [ "$RELEASE" = 1 ]; then SIGN_OPTIONS+=(--options runtime --timestamp); fi
if [ -n "${SIGN_KEYCHAIN:-}" ]; then SIGN_OPTIONS+=(--keychain "$SIGN_KEYCHAIN"); fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
# Sign nested code inside-out. Never use --deep: Downloader carries its own entitlements.
VERSION_DIR="$FRAMEWORK/Versions/B"
for nested in "$VERSION_DIR/XPCServices/Installer.xpc" "$VERSION_DIR/XPCServices/Downloader.xpc" "$VERSION_DIR/Autoupdate" "$VERSION_DIR/Updater.app"; do
  if [ -e "$nested" ]; then
    if [[ "$nested" == *Downloader.xpc ]]; then
      codesign "${SIGN_OPTIONS[@]}" --preserve-metadata=entitlements "$nested"
    else
      codesign "${SIGN_OPTIONS[@]}" "$nested"
    fi
  fi
done
codesign "${SIGN_OPTIONS[@]}" "$FRAMEWORK"
codesign "${SIGN_OPTIONS[@]}" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built: $(pwd)/$APP"
