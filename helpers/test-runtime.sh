#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
. helpers/swift-env.sh
OUT="$(mktemp -d "${TMPDIR:-/tmp}/hypermug-runtime-check.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
compile_core_module "$OUT/core"
swiftc -parse-as-library "${SWIFT_BASE_FLAGS[@]}" -module-name HyperMugProcessChecks \
  -I "$OUT/core" Source/HyperMug/Sources/Platform/ShellExecutor.swift \
  Source/HyperMug/PlatformTests/ShellExecutorTests.swift "$OUT/core/HyperMugCore.o" -o "$OUT/shell-checks"
"$OUT/shell-checks"
swiftc -parse-as-library "${SWIFT_BASE_FLAGS[@]}" -module-name HyperMugNotificationChecks \
  -I "$OUT/core" Source/HyperMug/Sources/App/IssueNotifications.swift \
  Source/HyperMug/Sources/Platform/Logging.swift Source/HyperMug/Sources/Platform/DebugLog.swift \
  Source/HyperMug/PlatformTests/IssueNotificationTests.swift "$OUT/core/HyperMugCore.o" -o "$OUT/notification-checks"
"$OUT/notification-checks"
