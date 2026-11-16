# Shared Swift build settings. Sourced (not executed) by build.sh, helpers/test.sh and
# helpers/compile-check.sh, so the target and the Core module flags exist in exactly one place.
# SDKROOT: a value set by the caller is used as is. If it is unset, the default SDK is probed with one
# trivial compile; when that fails (Command Line Tools whose newest SDK is newer than the compiler), the
# SDKs next to the toolchain are tried newest first and the first one that compiles is exported.

TARGET=arm64-apple-macos14

# Flags every swiftc invocation shares.
SWIFT_BASE_FLAGS=(-swift-version 5 -target "$TARGET")

swift_env_probe() { # compiles a trivial file against the current SDKROOT (or the default SDK)
  local dir ok=0
  dir="$(mktemp -d "${TMPDIR:-/tmp}/hypermug-sdk-probe.XXXXXX")"
  printf 'import Foundation\nlet x = 1\n' > "$dir/probe.swift"
  if swiftc -typecheck "${SWIFT_BASE_FLAGS[@]}" "$dir/probe.swift" >/dev/null 2>&1; then ok=1; fi
  rm -rf "$dir"
  [ "$ok" = 1 ]
}

swift_env_select_sdk() {
  local dev sdk sdks cache key preset="${SDKROOT:-}" result
  dev="$(xcode-select -p 2>/dev/null || true)"
  sdks="$(
    for d in "$dev/SDKs" /Library/Developer/CommandLineTools/SDKs; do
      ls -d "$d"/MacOSX[0-9]*.sdk 2>/dev/null || true
    done | sort -r -V -u
  )"

  # A failed probe costs seconds, so the outcome is cached for a day, keyed by the compiler version, the
  # toolchain location, the SDK list and the preset SDKROOT. The cache file holds one line: `keep` (the
  # environment as it is works), `unset` (the preset is broken, the default SDK works) or the SDK to use.
  key="$( { swiftc --version 2>&1; echo "$dev"; echo "$sdks"; echo "preset=$preset"; } | shasum | cut -c1-16)"
  cache="${TMPDIR:-/tmp}/hypermug-sdk-$key"
  result=""
  if [ -n "$(find "$cache" -mtime -1 2>/dev/null)" ]; then
    result="$(cat "$cache")"
    if [ -d "$result" ] || [ "$result" = keep ] || [ "$result" = unset ]; then :; else result=""; fi
  fi

  if [ -z "$result" ]; then
    # The preset SDKROOT is not trusted: Apple's /usr/bin/git shim exports one that can be newer than the
    # compiler, into every hook environment.
    if swift_env_probe; then
      result=keep
    else
      if [ -n "$preset" ]; then
        echo "swift-env: SDKROOT=$preset does not work with this swiftc; auto-selecting" >&2
        unset SDKROOT
        if swift_env_probe; then result=unset; fi
      fi
      if [ -z "$result" ]; then
        for sdk in $sdks; do
          if SDKROOT="$sdk" swift_env_probe; then result="$sdk"; break; fi
        done
      fi
    fi
    if [ -z "$result" ]; then
      echo "swift-env: no macOS SDK compiles with this swiftc ($(swiftc --version 2>&1 | head -1))." >&2
      echo "swift-env: install a matching Xcode / Command Line Tools, or set SDKROOT to a working SDK." >&2
      return 1
    fi
    printf '%s\n' "$result" > "$cache"
  elif [ "$result" != keep ] && [ -n "$preset" ]; then
    echo "swift-env: SDKROOT=$preset does not work with this swiftc; auto-selecting" >&2
  fi

  case "$result" in
    keep) ;;
    unset) unset SDKROOT ;;
    *)
      export SDKROOT="$result"
      echo "swift-env: using SDK $result" >&2
      ;;
  esac
}
swift_env_select_sdk || exit 1

# Core is its own module with one WMO object (+ .swiftmodule). Platform and App see only its `public` API.
# Release flags; test.sh compiles Core separately (instrumented, with -enable-testing).
compile_core_module() { # out-dir
  local out="$1"
  mkdir -p "$out"
  swiftc -O -wmo -parse-as-library "${SWIFT_BASE_FLAGS[@]}" \
    -module-name HyperMugCore -emit-module -emit-module-path "$out/HyperMugCore.swiftmodule" \
    -c -o "$out/HyperMugCore.o" Source/HyperMug/Sources/Core/*.swift
}
