#!/usr/bin/env bash
# Enforces the layer rules. Prints `file:line: rule` for every violation and exits 1 if there are any.
#
#   Sources/Core      pure logic, module HyperMugCore. Imports only Foundation, CoreGraphics, Dispatch and
#                     touches no OS service directly (those come in through injected closures/protocols).
#   Sources/Platform  thin OS adapters. May import Core. Must not use App.
#   Sources/App       AppKit UI and composition root. May use Platform and Core.
#   Tests             test Core only.
#
# Usage: helpers/check-layers.sh [repo-root]   (defaults to the parent of this script)
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../Source/HyperMug" && pwd)}"
cd "$ROOT"

violations=0
violation() { # file line rule
  echo "$1:$2: $3"
  violations=$((violations + 1))
}

swift_files() { # dir... -> every .swift file below the given dirs that exist
  for d in "$@"; do
    if [ -d "$d" ]; then find "$d" -name '*.swift' -type f; fi
  done | LC_ALL=C sort
}

# One import declaration: `[@attr[(args)] ...] [access] import [kind] Module[.Sub]`. Attributes cover
# @testable, @_exported, @preconcurrency, @_spi(X); access covers Swift 6 `public import` etc.
IMPORT_PREFIX='^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|internal|package|private|fileprivate)[[:space:]]+)*import[[:space:]]+((class|struct|enum|protocol|func|var|let|typealias)[[:space:]]+)?'
IMPORT_RE="${IMPORT_PREFIX}[A-Za-z_][A-Za-z0-9_]*"
IMPORT_MODULE_SED="s/${IMPORT_PREFIX}([A-Za-z_][A-Za-z0-9_]*).*/\\7/"

# grep -n for a pattern, skipping `//` comment lines. Output: "line:text".
grep_code() { # pattern file
  { grep -nE -e "$1" "$2" || true; } | { grep -vE '^[0-9]+:[[:space:]]*//' || true; }
}

# Every statement of every non-comment line, split on `;`, as "line:statement" (so `import A; import B`
# yields two entries).
statements() { # file
  awk '/^[[:space:]]*\/\// { next }
       { n = split($0, parts, ";"); for (i = 1; i <= n; i++) print NR ":" parts[i] }' "$1"
}

check_imports() { # file allowed-modules (space separated) allow-testable-module
  local file="$1" allowed="$2" testable_ok="$3" line text module
  while IFS= read -r line; do
    text="${line#*:}"
    module="$(printf '%s\n' "$text" | sed -E "$IMPORT_MODULE_SED")"
    case " $allowed " in
      *" $module "*) ;;
      *) violation "$file" "${line%%:*}" "import $module is not allowed here (allowed: $allowed)"; continue ;;
    esac
    case "$text" in
      *@testable*)
        if [ "$module" != "$testable_ok" ]; then
          violation "$file" "${line%%:*}" "@testable import $module is not allowed"
        fi
        ;;
    esac
  done < <(statements "$file" | { grep -E -e "^[0-9]+:${IMPORT_RE#^}" || true; })
}

# ---- 1. No stray sources; layers are flat ----------------------------------------------------
# build.sh and test.sh compile `Sources/<layer>/*.swift` and `Tests/*.swift` non-recursively, so a file in
# a subfolder would escape the build and the coverage gate: subfolders are rejected.
if [ -d Sources ]; then
  while IFS= read -r f; do
    case "$f" in
      Sources/Core/*/*|Sources/Platform/*/*|Sources/App/*/*)
        violation "$f" 1 "layers are flat: no subfolders inside Sources/{Core,Platform,App}/" ;;
      Sources/Core/*|Sources/Platform/*|Sources/App/*) ;;
      *) violation "$f" 1 "source file outside Sources/{Core,Platform,App}/" ;;
    esac
  done < <(swift_files Sources)
fi
while IFS= read -r f; do
  case "$f" in
    Tests/*/*) violation "$f" 1 "Tests/ is flat: no subfolders (test.sh compiles Tests/*.swift)" ;;
  esac
done < <(swift_files Tests)

# ---- 2. Core imports -------------------------------------------------------------------------
while IFS= read -r f; do
  check_imports "$f" "Foundation CoreGraphics Dispatch" ""
done < <(swift_files Sources/Core)

# ---- 3. Core forbidden API -------------------------------------------------------------------
# Foundation re-exports Darwin, so the import check alone is not enough. Every hit is a side effect
# that has to come in through injection. FileManager and Data.write/contentsOf stay allowed: the config
# store and schema install are Core and are tested in temp dirs.
FORBIDDEN=(
  # processes
  '\bProcess\(' '\bposix_spawn' '\bkill(pg)?\(' '\bwaitpid\(' '\bsystem\(' '\bpopen\(' '\bexec[lv]p?\('
  # identity and environment
  '\bgetuid\(' '\bgetpwuid\(' '\bproc_(name|pidpath|pidinfo)\(' '\bProcessInfo\b'
  # OS services
  '\bUserDefaults\b' '\bNSWorkspace\b' '\bNSRunningApplication\b' '\bURLSession\b'
  # run loop and dispatch
  '\bDispatchSource\b' '\bDispatchQueue\.main\b' '\bTimer\b' '\bRunLoop\b'
  # clocks
  '\bDate\(\)' 'DispatchTime\.now\(\)'
  # home directory
  'homeDirectoryForCurrentUser' 'NSHomeDirectory\('
  # low-level file calls
  '\bO_EVTONLY\b' '\bfstat\(' '(^|[^.A-Za-z0-9_])stat\('
  # output
  '\bLogger\b' '\bos_log\b' '\bNSLog\(' '\bprint\('
  # events
  'CGEvent\(' '\.tapCreate\b' '\.post\(tap:'
)
while IFS= read -r f; do
  for pattern in "${FORBIDDEN[@]}"; do
    while IFS= read -r hit; do
      violation "$f" "${hit%%:*}" "forbidden in Core (inject it from Platform): /$pattern/"
    done < <(grep_code "$pattern" "$f")
  done
done < <(swift_files Sources/Core)

# ---- 4. Platform must not use App ------------------------------------------------------------
# App identifiers: every top-level (column 0) non-private declaration in Sources/App, plus a fixed
# safety net. `extension`s are skipped (extending a Core or Platform type from App is legal).
DECL_RE='^((public|internal|open|final)[[:space:]]+|@[A-Za-z_]+[[:space:]]+)*(class|struct|enum|protocol|typealias|func|let|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*'
APP_NAMES=" AppDelegate HyperMugMain StatusItemController SecureInputWindowController ConfigErrorAlert PrivilegesPresenter presentUpdateAlert "
while IFS= read -r f; do
  while IFS= read -r line; do
    name="$(printf '%s\n' "$line" | sed -E 's/^((public|internal|open|final)[[:space:]]+|@[A-Za-z_]+[[:space:]]+)*(class|struct|enum|protocol|typealias|func|let|var)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\4/')"
    case "$APP_NAMES" in
      *" $name "*) ;;
      *) APP_NAMES="$APP_NAMES$name " ;;
    esac
  done < <(grep -E "$DECL_RE" "$f" || true)
done < <(swift_files Sources/App)

while IFS= read -r f; do
  for name in $APP_NAMES; do
    while IFS= read -r hit; do
      violation "$f" "${hit%%:*}" "Platform must not use App (references $name)"
    done < <(grep_code "\\b$name\\b" "$f")
  done
done < <(swift_files Sources/Platform)

# ---- 5. Tests touch only Core ----------------------------------------------------------------
while IFS= read -r f; do
  check_imports "$f" "Foundation CoreGraphics Carbon HyperMugCore" "HyperMugCore"
done < <(swift_files Tests)

# ---- 6. No selftest remnants -----------------------------------------------------------------
if [ -d Sources ]; then
  while IFS= read -r f; do
    while IFS= read -r hit; do
      violation "$f" "${hit%%:*}" "selftest remnant (selftests live in Tests/)"
    done < <(grep -nE -e '--selftest|selfTest|runSelfTest' "$f" || true)
  done < <(swift_files Sources)
fi

if [ "$violations" -gt 0 ]; then
  echo "check-layers: $violations violation(s)" >&2
  exit 1
fi
echo "check-layers: ok"
