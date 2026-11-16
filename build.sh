#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
./scripts/check-layers.sh

APP=build/HyperMug.app
CORE=build/core
TARGET=arm64-apple-macos14
rm -rf "$APP" "$CORE"
mkdir -p "$APP/Contents/MacOS" "$CORE"

# Core: its own module, one WMO object (+ .swiftmodule). Platform and App see only its `public` API.
swiftc -O -wmo -parse-as-library -swift-version 5 -target "$TARGET" \
  -module-name HyperMugCore -emit-module -emit-module-path "$CORE/HyperMugCore.swiftmodule" \
  -c -o "$CORE/HyperMugCore.o" Sources/Core/*.swift

swiftc -O -parse-as-library -swift-version 5 -target "$TARGET" -module-name HyperMug \
  -I "$CORE" Sources/Platform/*.swift Sources/App/*.swift "$CORE/HyperMugCore.o" \
  -o "$APP/Contents/MacOS/HyperMug" -framework IOKit -framework Carbon

cp Info.plist "$APP/Contents/"

SIGN_ID="${SIGN_ID:-HyperMug Local Signing}"
# Not `-v`: a self-signed identity is untrusted but valid for codesign.
if security find-identity -p codesigning | grep -q "$SIGN_ID"; then
  codesign --force --sign "$SIGN_ID" --identifier com.max.hypermug "$APP"
else
  echo "warning: identity $SIGN_ID not found; signing ad-hoc (-)."
  echo "         Run ./scripts/create-signing-cert.sh once so permissions survive rebuilds."
  codesign --force --sign - "$APP"
fi

echo "Built: $(pwd)/$APP"
