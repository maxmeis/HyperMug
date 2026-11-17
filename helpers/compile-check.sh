#!/usr/bin/env bash
# Fast compile gate: builds the HyperMugCore module and type-checks Platform + App against it. No app
# bundle, no linking, no signing. Everything goes into a temp dir that is removed on exit.
# SDKROOT is optional (see swift-env.sh). Exits non-zero on any compile error.
set -euo pipefail
cd "$(dirname "$0")/.."
. helpers/swift-env.sh

OUT="$(mktemp -d "${TMPDIR:-/tmp}/hypermug-compile-check.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT

compile_core_module "$OUT/core"

swiftc -typecheck -parse-as-library "${SWIFT_BASE_FLAGS[@]}" -module-name HyperMug \
  -I "$OUT/core" Source/HyperMug/Sources/Platform/*.swift Source/HyperMug/Sources/App/*.swift

echo "compile-check: ok"
