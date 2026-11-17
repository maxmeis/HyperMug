#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
. helpers/swift-env.sh
# The launcher links Core so it can copy settings with the app's own TOML reader and writer.
OUT="$(mktemp -d "${TMPDIR:-/tmp}/hypermug-run-local.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
compile_core_module "$OUT/core"
swiftc "${SWIFT_BASE_FLAGS[@]}" -I "$OUT/core" helpers/run-local.swift "$OUT/core/HyperMugCore.o" -o "$OUT/run-local"
"$OUT/run-local" "$PWD/build/HyperMug Dev.app"
