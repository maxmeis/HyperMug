#!/usr/bin/env bash
# Publish one immutable archive, then commit its signed Sparkle appcast to the
# updates branch and its verified cask to the source tap.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
: "${VERSION:?}" "${GITHUB_SHA:?}" "${GITHUB_REPOSITORY:?}" "${GH_TOKEN:?}" "${APPLE_TEAM_ID:?}"
# Fail before any release state changes: an unsigned release would never reach Sparkle users.
[[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]] || { echo 'SPARKLE_ED_PRIVATE_KEY is required to sign the appcast' >&2; exit 1; }
[[ "$GITHUB_REPOSITORY" == maxmeis/hypermug && "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo 'Invalid production release' >&2; exit 1; }
tag="v$VERSION"
asset="HyperMug-${VERSION}.zip"
[[ "$(git rev-parse "${tag}^{commit}")" == "$GITHUB_SHA" ]] || { echo 'Release tag points to a different commit' >&2; exit 1; }
archive="build/release/$asset"
test -s "$archive"
local_digest="$(shasum -a 256 "$archive" | awk '{print $1}')"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
. helpers/sparkle.sh
sparkle_prepare
notes="HyperMug $VERSION; source $GITHUB_SHA"
if gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json body >/dev/null 2>&1; then
  body="$(gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json body --jq .body)"
  [[ "$body" == "$notes" ]] || { echo 'Existing release belongs to a different source' >&2; exit 1; }
  is_draft="$(gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json isDraft --jq .isDraft)"
  if gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json assets --jq '.assets[].name' | grep -Fxq "$asset"; then
    local_digest=''
  elif [[ "$is_draft" == true ]]; then
    gh release upload "$tag" "$archive" --repo "$GITHUB_REPOSITORY"
  else
    echo 'Published release is missing its immutable app archive' >&2; exit 1
  fi
else
  gh release create "$tag" "$archive" --repo "$GITHUB_REPOSITORY" --draft --title "HyperMug $VERSION" --notes "$notes"
  is_draft=true
fi
# The cask is always derived from the published archive bytes, including retries.
gh release download "$tag" --repo "$GITHUB_REPOSITORY" --pattern "$asset" --dir "$work"
archive="$work/$asset"
test -s "$archive"
actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
[[ -z "$local_digest" || "$actual" == "$local_digest" ]] || { echo 'Uploaded archive digest differs from final local archive' >&2; exit 1; }
./helpers/verify_release_archive.sh "$archive" "$VERSION" "$APPLE_TEAM_ID"
python3 helpers/release_metadata.py cask --version "$VERSION" --zip "$archive" --output "$work/hypermug.rb"
[[ "$actual" == "$(sed -n 's/^  sha256 "\([0-9a-f]*\)"$/\1/p' "$work/hypermug.rb")" ]] || exit 1
# Sign the exact downloaded bytes. The key travels only over stdin, never in arguments or logs.
signature="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SPARKLE_ROOT/bin/sign_update" --ed-key-file - -p "$archive")"
unset SPARKLE_ED_PRIVATE_KEY
# Fails unless the signature verifies with the SUPublicEDKey inside this archive.
python3 helpers/release_metadata.py appcast --version "$VERSION" --zip "$archive" --signature "$signature" --output "$work/appcast-stable.xml"
if [[ "$is_draft" == true ]]; then
  latest_tag="$(gh api "repos/$GITHUB_REPOSITORY/releases/latest" --jq .tag_name 2> "$work/latest-error")" || {
    if grep -q 'HTTP 404' "$work/latest-error"; then latest_tag=''; else cat "$work/latest-error" >&2; exit 1; fi
  }
  latest_flag="$(python3 - "$latest_tag" "$VERSION" <<'PY'
import re, sys
latest, candidate = sys.argv[1:]
match = re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', latest)
print('--latest=false' if match and tuple(map(int, match.groups())) > tuple(map(int, candidate.split('.'))) else '--latest')
PY
)"
  gh release edit "$tag" --repo "$GITHUB_REPOSITORY" --draft=false "$latest_flag"
fi
# Use a narrow, repository-scoped deploy key when protected main requires its
# configured deploy-key bypass. Otherwise the built-in token can write directly.
if [[ -n "${HOMEBREW_SSH_PRIVATE_KEY:-}" ]]; then
  printf '%s\n' "$HOMEBREW_SSH_PRIVATE_KEY" > "$work/homebrew-key"
  gh api meta --jq '.ssh_keys[]' | sed 's/^/github.com /' > "$work/known-hosts"
  test -s "$work/known-hosts"
  export GIT_SSH_COMMAND="ssh -F /dev/null -i $work/homebrew-key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$work/known-hosts"
  git remote set-url origin "git@github.com:${GITHUB_REPOSITORY}.git"
else
  # GITHUB_TOKEN pushes do not trigger another workflow. Keep its credential
  # process-local, never in Git remotes or on disk.
  export GIT_CONFIG_COUNT="${GIT_CONFIG_COUNT:-0}"
  slot="$GIT_CONFIG_COUNT"
  export GIT_CONFIG_COUNT="$((slot + 1))"
  export "GIT_CONFIG_KEY_${slot}=http.https://github.com/.extraheader"
  export "GIT_CONFIG_VALUE_${slot}=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
fi
# The feed lives on its own branch in a scratch repository so this checkout,
# including the running helpers, is untouched. Sparkle reads it via raw URLs.
origin_url="$(git remote get-url origin)"
feed="$work/updates"
for attempt in 1 2 3; do
  rm -rf "$feed"
  git init -q "$feed"
  git -C "$feed" remote add origin "$origin_url"
  if git -C "$feed" ls-remote --exit-code origin refs/heads/updates >/dev/null; then
    git -C "$feed" fetch -q origin updates
    git -C "$feed" checkout -q --detach FETCH_HEAD
  else
    status=$?
    [[ "$status" == 2 ]] || { echo 'Cannot read the updates branch' >&2; exit 1; }
  fi
  decision="$(python3 helpers/release_metadata.py feed-decision --current "$feed/appcast-stable.xml" --candidate "$work/appcast-stable.xml")"
  if [[ "$decision" == newer ]]; then echo 'A newer production appcast is already published'; break; fi
  if [[ "$decision" == current ]]; then break; fi
  cp "$work/appcast-stable.xml" "$feed/appcast-stable.xml"
  git -C "$feed" add appcast-stable.xml
  git -C "$feed" -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' commit -qm "chore: update production appcast to $VERSION"
  if git -C "$feed" push origin HEAD:refs/heads/updates; then break; fi
  if [[ "$attempt" == 3 ]]; then echo 'Cannot commit appcast to the updates branch; check the publishing credential and branch rules' >&2; exit 1; fi
done
for attempt in 1 2 3; do
  git fetch origin main
  git checkout --detach origin/main
  old=''
  if [[ -f Casks/hypermug.rb ]]; then old="$(sed -n 's/^  version "\([0-9.]*\)"$/\1/p' Casks/hypermug.rb)"; fi
  decision="$(python3 - "$old" "$VERSION" <<'PY'
import sys
import re
old, new = sys.argv[1:]
if old and not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', old):
    raise SystemExit('invalid current cask version')
if old and tuple(map(int, old.split('.'))) > tuple(map(int, new.split('.'))): print('newer')
else: print('proceed')
PY
)"
  if [[ "$decision" == newer ]]; then echo 'A newer production cask is already published'; exit 0; fi
  if cmp -s "$work/hypermug.rb" Casks/hypermug.rb; then exit 0; fi
  if [[ "$old" == "$VERSION" ]]; then echo 'Current cask version has different immutable asset bytes' >&2; exit 1; fi
  cp "$work/hypermug.rb" Casks/hypermug.rb
  git add Casks/hypermug.rb
  git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' commit -m "chore: update Homebrew cask to $VERSION"
  if git push origin HEAD:main; then exit 0; fi
  if [[ "$attempt" == 3 ]]; then echo 'Cannot commit cask to protected main; check the configured publishing credential and branch rules' >&2; exit 1; fi
done
