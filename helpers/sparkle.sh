#!/usr/bin/env bash
# Source this file to populate SPARKLE_ROOT (framework and bin/sign_update)
# and SPARKLE_FRAMEWORK_DIR (parent of Sparkle.framework).
SPARKLE_VERSION=2.10.1
SPARKLE_SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE_ROOT="$PWD/build/deps/Sparkle-$SPARKLE_VERSION"
SPARKLE_FRAMEWORK_DIR="$SPARKLE_ROOT"
sparkle_prepare() {
  local archive="$PWD/build/deps/Sparkle-$SPARKLE_VERSION.tar.xz" actual
  mkdir -p "$PWD/build/deps"
  if [ ! -f "$archive" ]; then
    curl -fL --retry 3 -o "$archive.tmp" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    mv "$archive.tmp" "$archive"
  fi
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [ "$actual" != "$SPARKLE_SHA256" ]; then
    echo "error: Sparkle archive SHA256 mismatch: $actual" >&2
    return 1
  fi
  if [ ! -d "$SPARKLE_ROOT/Sparkle.framework" ]; then
    mkdir -p "$SPARKLE_ROOT"
    tar -xJf "$archive" -C "$SPARKLE_ROOT"
  fi
  test -d "$SPARKLE_ROOT/Sparkle.framework" && test -x "$SPARKLE_ROOT/bin/sign_update"
}
