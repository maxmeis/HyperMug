#!/usr/bin/env bash
# Builds Core + Tests with coverage instrumentation, runs the tests and fails unless every executable
# line of Source/HyperMug/Sources/Core is covered. Run it as:
#   SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./helpers/test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
./helpers/check-layers.sh
. helpers/swift-env.sh

OUT=build/test
rm -rf "$OUT"
mkdir -p "$OUT"

# Core is compiled to ONE whole-module object and linked as that object, NOT as a static archive: the
# linker drops archive members nothing references, so an untested file would silently vanish from the
# coverage report and the gate would show a false 100%. -enable-testing is for this build only (the tests
# use `@testable import HyperMugCore`); build.sh compiles Core without it.
swiftc -Onone -enable-testing -profile-generate -profile-coverage-mapping -wmo -parse-as-library \
  "${SWIFT_BASE_FLAGS[@]}" -module-name HyperMugCore \
  -emit-module -emit-module-path "$OUT/HyperMugCore.swiftmodule" \
  -c -o "$OUT/HyperMugCore.o" Source/HyperMug/Sources/Core/*.swift

# Source/HyperMug/Tests/main.swift is the entry point, so no -parse-as-library here.
swiftc -Onone -profile-generate "${SWIFT_BASE_FLAGS[@]}" -module-name HyperMugCoreTests \
  -I "$OUT" Source/HyperMug/Tests/*.swift "$OUT/HyperMugCore.o" -o "$OUT/HyperMugCoreTests"

# Non-zero exit on any failed expectation stops the script (set -e).
LLVM_PROFILE_FILE="$OUT/core.profraw" "$OUT/HyperMugCoreTests"

xcrun llvm-profdata merge -sparse "$OUT/core.profraw" -o "$OUT/core.profdata"
xcrun llvm-cov report "$OUT/HyperMugCoreTests" -instr-profile "$OUT/core.profdata" Source/HyperMug/Sources/Core
xcrun llvm-cov export -format=lcov "$OUT/HyperMugCoreTests" -instr-profile "$OUT/core.profdata" Source/HyperMug/Sources/Core \
  > "$OUT/core.lcov"

# Core files with no executable lines (types and constants only) are absent from the lcov: informational.
for f in Source/HyperMug/Sources/Core/*.swift; do
  if ! grep -q "^SF:.*/$f\$" "$OUT/core.lcov"; then
    echo "info: $f has no executable lines"
  fi
done

# Sum the per-line counts; list every uncovered line; fail unless all lines are covered.
awk -v root="$PWD/" '
  /^SF:/ { file = substr($0, 4); sub("^" root, "", file); next }
  /^DA:/ {
    split(substr($0, 4), da, ",")
    total++
    if (da[2] + 0 == 0) { missed[++n] = file ":" da[1] } else { hit++ }
  }
  END {
    pct = total ? 100 * hit / total : 0
    printf "Core line coverage: %d/%d (%.2f%%)\n", hit, total, pct
    if (total == 0) { print "error: no executable Core lines found in the coverage data"; exit 1 }
    if (hit != total) {
      print "Uncovered lines:"
      for (i = 1; i <= n; i++) print "  " missed[i]
      exit 1
    }
  }
' "$OUT/core.lcov"
