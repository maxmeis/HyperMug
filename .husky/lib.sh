# Sourced by the hooks in this folder (POSIX sh). Not a hook itself.

# GUI git clients (and the T3 app) often start hooks without the Volta shims on PATH.
if [ -d "$HOME/.volta/bin" ]; then
  PATH="$HOME/.volta/bin:$PATH"
  export PATH
fi

# Husky points core.hooksPath at .husky/_, which bypasses the repo's vendored hooks in
# $(git rev-parse --git-common-dir)/hooks/ (commit-signing check, gitleaks). Run the vendored hook of the
# same name first, if it exists and is executable. Arguments and stdin pass through; a failure fails the
# calling hook. Never edit the vendored hooks.
#   usage: run_vendored_hook <hook-name> "$@"
run_vendored_hook() {
  hook_name="$1"
  shift
  vendored="$(git rev-parse --git-common-dir)/hooks/$hook_name"
  if [ -x "$vendored" ]; then
    "$vendored" "$@" || exit $?
  fi
}
