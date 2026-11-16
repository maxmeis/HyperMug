#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
./scripts/check-layers.sh
. scripts/swift-env.sh

APP=build/HyperMug.app
CORE=build/core
rm -rf "$APP" "$CORE"
mkdir -p "$APP/Contents/MacOS"

compile_core_module "$CORE"

swiftc -O -parse-as-library "${SWIFT_BASE_FLAGS[@]}" -module-name HyperMug \
  -I "$CORE" Sources/Platform/*.swift Sources/App/*.swift "$CORE/HyperMugCore.o" \
  -o "$APP/Contents/MacOS/HyperMug" -framework IOKit -framework Carbon

cp Info.plist "$APP/Contents/"

SIGN_ID="${SIGN_ID:-HyperMug Local Signing}"
# Not `-v`: a self-signed identity is untrusted but valid for codesign.
if security find-identity -p codesigning | grep -q "$SIGN_ID"; then
  codesign --force --sign "$SIGN_ID" --identifier com.maxmeis.hypermug "$APP"
else
  echo "warning: identity $SIGN_ID not found; signing ad-hoc (-)."
  echo "         Run ./scripts/create-signing-cert.sh once so permissions survive rebuilds."
  codesign --force --sign - "$APP"
fi

echo "Built: $(pwd)/$APP"
