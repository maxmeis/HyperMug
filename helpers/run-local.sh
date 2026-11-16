#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
. helpers/swift-env.sh
swift "${SWIFT_BASE_FLAGS[@]}" helpers/run-local.swift "$PWD/build/HyperMug Dev.app"
