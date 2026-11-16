#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
./scripts/check-layers.sh
. scripts/swift-env.sh
. scripts/sparkle.sh
sparkle_prepare

APP=build/HyperMug.app
CORE=build/core
VERSION="${APP_VERSION:-0.1}"
NUMBER="${BUILD_NUMBER:-1}"
CHANNEL="${UPDATE_CHANNEL:-stable}"
REPOSITORY="${RELEASES_REPOSITORY:-maxmeis/HyperMug}"
FEED="${APPCAST_URL:-https://raw.githubusercontent.com/${REPOSITORY}/updates/appcast-${CHANNEL}.xml}"
KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
RELEASE="${REQUIRE_SIGNING:-0}"
case "$CHANNEL" in stable|beta) ;; *) echo "error: UPDATE_CHANNEL must be stable or beta" >&2; exit 1;; esac
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*([.-][A-Za-z0-9]+)*$ ]] || { echo "error: invalid APP_VERSION" >&2; exit 1; }
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
rm -rf "$APP" "$CORE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
compile_core_module "$CORE"
swiftc -O -parse-as-library "${SWIFT_BASE_FLAGS[@]}" -module-name HyperMug \
  -I "$CORE" -F "$SPARKLE_FRAMEWORK_DIR" Sources/Platform/*.swift Sources/App/*.swift "$CORE/HyperMugCore.o" \
  -o "$APP/Contents/MacOS/HyperMug" -framework IOKit -framework Carbon -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks
cp -R "$SPARKLE_FRAMEWORK_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
cp Info.plist "$APP/Contents/"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NUMBER" "$PLIST"
if [ -n "$KEY" ]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $FEED" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $KEY" "$PLIST"
else
  echo "warning: updates disabled; set SPARKLE_PUBLIC_ED_KEY and APPCAST_URL to enable."
fi
SIGN_ID="${SIGN_ID:-HyperMug Local Signing}"
if [ "$RELEASE" != 1 ] && ! security find-identity -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} | grep -Fq "\"$SIGN_ID\""; then
  echo "warning: identity $SIGN_ID not found; signing ad-hoc (-)."
  SIGN_ID=-
fi
SIGN_OPTIONS=()
if [ "$RELEASE" = 1 ]; then SIGN_OPTIONS=(--options runtime --timestamp); fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
# Sign nested code inside-out. Never use --deep: Downloader carries its own entitlements.
VERSION_DIR="$FRAMEWORK/Versions/B"
for nested in "$VERSION_DIR/XPCServices/Installer.xpc" "$VERSION_DIR/XPCServices/Downloader.xpc" "$VERSION_DIR/Autoupdate" "$VERSION_DIR/Updater.app"; do
  if [ -e "$nested" ]; then
    if [[ "$nested" == *Downloader.xpc ]]; then
      codesign --force --sign "$SIGN_ID" "${SIGN_OPTIONS[@]}" --preserve-metadata=entitlements ${SIGN_KEYCHAIN:+--keychain "$SIGN_KEYCHAIN"} "$nested"
    else
      codesign --force --sign "$SIGN_ID" "${SIGN_OPTIONS[@]}" ${SIGN_KEYCHAIN:+--keychain "$SIGN_KEYCHAIN"} "$nested"
    fi
  fi
done
codesign --force --sign "$SIGN_ID" "${SIGN_OPTIONS[@]}" ${SIGN_KEYCHAIN:+--keychain "$SIGN_KEYCHAIN"} "$FRAMEWORK"
codesign --force --sign "$SIGN_ID" "${SIGN_OPTIONS[@]}" ${SIGN_KEYCHAIN:+--keychain "$SIGN_KEYCHAIN"} --identifier com.maxmeis.hypermug "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built: $(pwd)/$APP"
