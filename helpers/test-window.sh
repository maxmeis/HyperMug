#!/usr/bin/env bash
# Interactive native-window checks: temporary config and app, no engine/capture/permission requests.
set -euo pipefail
cd "$(dirname "$0")/.."
. helpers/swift-env.sh
. helpers/sparkle.sh
sparkle_prepare
SWIFT_BASE_FLAGS+=(-D HYPERMUG_DEV)
out="$(mktemp -d "${TMPDIR:-/tmp}/hypermug-window-check.XXXXXX")"
trap 'rm -rf "$out"' EXIT
mkdir -p "$out/HyperMug UI Check.app/Contents/MacOS" "$out/HyperMug UI Check.app/Contents/Resources"
compile_core_module "$out/core"
swiftc -parse-as-library -module-name HyperMug "${SWIFT_BASE_FLAGS[@]}" -I "$out/core" -F "$SPARKLE_FRAMEWORK_DIR" \
  Source/HyperMug/Sources/Platform/*.swift Source/HyperMug/Sources/App/ConfigurationEditor.swift \
  Source/HyperMug/Sources/App/HyperMugWindow.swift Source/HyperMug/Sources/App/ApplicationMenu.swift \
  Source/HyperMug/Sources/App/PrivilegesAlert.swift Source/HyperMug/WindowTests/main.swift \
  "$out/core/HyperMugCore.o" -framework IOKit -framework Carbon -framework Sparkle \
  -Xlinker -rpath -Xlinker "$SPARKLE_FRAMEWORK_DIR" \
  -o "$out/HyperMug UI Check.app/Contents/MacOS/HyperMugWindowChecks"
python3 - "$out/HyperMug UI Check.app" <<'PY'
from pathlib import Path
import plistlib,sys
app=Path(sys.argv[1])
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='com.maxmeis.hypermug.ui-check',CFBundleName='HyperMug UI Check',CFBundleExecutable='HyperMugWindowChecks',CFBundlePackageType='APPL',CFBundleShortVersionString='0.1.0',CFBundleVersion='1',HyperMugReleaseChannel='local',CFBundleIconFile='HyperMug.icns')))
PY
cp Source/Branding/HyperMug.icns "$out/HyperMug UI Check.app/Contents/Resources/"
swiftc -parse-as-library "${SWIFT_BASE_FLAGS[@]}" -I "$out/core" helpers/schema-main.swift "$out/core/HyperMugCore.o" -o "$out/render-schema"
"$out/render-schema" "$out/HyperMug UI Check.app/Contents/Resources"
"$out/HyperMug UI Check.app/Contents/MacOS/HyperMugWindowChecks"
