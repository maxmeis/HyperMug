#!/usr/bin/env bash
# Publish immutable assets first; channel pointers move only after both release and metadata exist.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CHANNEL:?}" "${VERSION:?}" "${BUILD_NUMBER:?}" "${BUILD_APP:?}" "${SOURCE_REPOSITORY:?}" "${RELEASES_REPOSITORY:?}" "${TAP_REPOSITORY:?}" "${RELEASE_TOKEN:?}" "${GITHUB_SHA:?}"
python3 scripts/release_metadata.py validate --channel "$CHANNEL" --version "$VERSION" --actor "$GITHUB_ACTOR" --triggering-actor "$GITHUB_TRIGGERING_ACTOR" --ref "$GITHUB_REF" --sha "$GITHUB_SHA" --source-repo "$SOURCE_REPOSITORY" --releases-repo "$RELEASES_REPOSITORY" --tap-repo "$TAP_REPOSITORY"
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || exit 1
[[ "$BUILD_APP" == true || "$BUILD_APP" == false ]] || { echo 'BUILD_APP must be true or false' >&2; exit 1; }
PUBLISH_EXTERNAL_TAP="${PUBLISH_EXTERNAL_TAP:-false}"
[[ "$PUBLISH_EXTERNAL_TAP" == true || "$PUBLISH_EXTERNAL_TAP" == false ]] || { echo 'PUBLISH_EXTERNAL_TAP must be true or false' >&2; exit 1; }
[[ "$CHANNEL" != canary || "$BUILD_APP" == true ]] || { echo 'Canary requires an app build' >&2; exit 1; }
if [[ "$BUILD_APP" == true && "$PUBLISH_EXTERNAL_TAP" == true && -z "${TAP_SSH_PRIVATE_KEY:-}" && -z "${TAP_TOKEN:-}" ]]; then
  echo 'TAP_SSH_PRIVATE_KEY or TAP_TOKEN is required' >&2
  exit 1
fi
export GH_TOKEN="$RELEASE_TOKEN"
if [[ "$BUILD_APP" == true && "$PUBLISH_EXTERNAL_TAP" == true ]]; then
  tap_archived="$(gh api "repos/${TAP_REPOSITORY}" --jq .archived)" || { echo 'External tap is unavailable; disable PUBLISH_EXTERNAL_TAP or repair its access' >&2; exit 1; }
  [[ "$tap_archived" == false ]] || { echo 'External tap is archived; disable PUBLISH_EXTERNAL_TAP or choose a writable destination' >&2; exit 1; }
fi
export PYTHONPATH="$PWD/scripts"
tag="v${VERSION}"
asset="HyperMug-${VERSION}.zip"
feed="appcast-${CHANNEL}.xml"
token=hypermug
if [[ "$CHANNEL" == canary ]]; then token='hypermug@canary'; fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# GitHub's commit endpoint peels an annotated tag. Existing tags are reusable only
# when they resolve to this exact built source commit.
source_tag_exists=0
if gh api "repos/${SOURCE_REPOSITORY}/git/ref/tags/${tag}" >/dev/null 2>&1; then
  source_tag_exists=1
  peeled="$(gh api "repos/${SOURCE_REPOSITORY}/commits/${tag}" --jq .sha)"
  [[ "$peeled" == "$GITHUB_SHA" ]] || { echo 'Existing source tag points elsewhere' >&2; exit 1; }
fi
release_exists=0
release_draft=false
release_body=''
release_assets=''
if gh release view "$tag" --repo "$RELEASES_REPOSITORY" >/dev/null 2>&1; then
  release_exists=1
  # The release body records the source SHA, particularly when assets live in
  # another repository whose tag necessarily points to a different commit.
  release_body="$(gh release view "$tag" --repo "$RELEASES_REPOSITORY" --json body --jq .body)"
  [[ "$release_body" == *"source ${GITHUB_SHA}"* ]] || { echo 'Existing release belongs to another source commit' >&2; exit 1; }
  release_draft="$(gh release view "$tag" --repo "$RELEASES_REPOSITORY" --json isDraft --jq .isDraft)"
  release_latest="$(gh release view "$tag" --repo "$RELEASES_REPOSITORY" --json isLatest --jq .isLatest)"
  release_assets="$(gh release view "$tag" --repo "$RELEASES_REPOSITORY" --json assets --jq '.assets[].name')"
fi
source_only_release=0
if [[ "$release_body" == *"source-only"* ]]; then source_only_release=1; fi
if [[ "$BUILD_APP" == false && "$release_exists" == 1 && "$source_only_release" == 1 && -z "$release_assets" && "$release_draft" == false ]]; then
  # Repeating a completed source-only release is a read-only no-op, even after
  # newer versions have been published.
  [[ "$(gh api "repos/${SOURCE_REPOSITORY}/commits/${tag}" --jq .sha)" == "$GITHUB_SHA" ]] || exit 1
  if [[ "$RELEASES_REPOSITORY" != "$SOURCE_REPOSITORY" ]]; then
    tag_object="$(gh api "repos/${RELEASES_REPOSITORY}/git/ref/tags/${tag}" --jq .object.sha)"
    [[ "$(gh api "repos/${RELEASES_REPOSITORY}/git/tags/${tag_object}" --jq .message)" == *"source ${GITHUB_SHA}"* ]] || exit 1
  fi
  if [[ "$release_latest" == true ]]; then
    gh release edit "$tag" --repo "$RELEASES_REPOSITORY" --latest=false
  fi
  exit 0
fi
gh api "repos/${RELEASES_REPOSITORY}/releases?per_page=100" --paginate --jq '.[].tag_name' > "$work/tags"
python3 - "$CHANNEL" "$VERSION" "$release_exists" "$work/tags" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, 'scripts')
from release_metadata import release_order
release_order(sys.argv[1], sys.argv[2], Path(sys.argv[4]).read_text().splitlines(), sys.argv[3] == '1')
PY
# The source tag must already exist and resolve to the checkout SHA.
[[ "$source_tag_exists" == 1 ]] || { echo "Production source tag is missing" >&2; exit 1; }
if [[ "$RELEASES_REPOSITORY" == "$SOURCE_REPOSITORY" ]]; then
  release_sha="$GITHUB_SHA"
  release_tag_exists="$source_tag_exists"
else
  release_sha="$(gh api "repos/${RELEASES_REPOSITORY}/commits/HEAD" --jq .sha)"
  release_tag_exists=0
  if gh api "repos/${RELEASES_REPOSITORY}/git/ref/tags/${tag}" >/dev/null 2>&1; then
    release_tag_exists=1
    tag_object="$(gh api "repos/${RELEASES_REPOSITORY}/git/ref/tags/${tag}" --jq .object.sha)"
    message="$(gh api "repos/${RELEASES_REPOSITORY}/git/tags/${tag_object}" --jq .message)"
    [[ "$message" == *"source ${GITHUB_SHA}"* ]] || { echo 'Release repository tag belongs to another source commit' >&2; exit 1; }
    release_sha="$(gh api "repos/${RELEASES_REPOSITORY}/commits/${tag}" --jq .sha)"
  fi
fi
if [[ "$release_tag_exists" == 1 && "$release_exists" == 0 ]]; then
  peeled="$(gh api "repos/${RELEASES_REPOSITORY}/commits/${tag}" --jq .sha)"
  [[ "$peeled" == "$release_sha" ]] || { echo 'Existing release tag points elsewhere' >&2; exit 1; }
fi
if [[ "$release_tag_exists" == 0 ]]; then
  object="$(gh api -X POST "repos/${RELEASES_REPOSITORY}/git/tags" -f tag="$tag" -f message="HyperMug ${VERSION}; source ${GITHUB_SHA}" -f object="$release_sha" -f type=commit --jq .sha)"
  gh api -X POST "repos/${RELEASES_REPOSITORY}/git/refs" -f ref="refs/tags/${tag}" -f sha="$object" >/dev/null
fi
if [[ "$BUILD_APP" == false ]]; then
  [[ "$release_exists" == 0 || ( "$source_only_release" == 1 && -z "$release_assets" ) ]] || { echo 'Existing release contains app assets or has another mode' >&2; exit 1; }
  if [[ "$release_exists" == 0 ]]; then
    gh release create "$tag" --repo "$RELEASES_REPOSITORY" --draft --title "HyperMug ${VERSION} (source only)" --notes "HyperMug source-only ${VERSION}; source ${GITHUB_SHA}"
  fi
  if [[ "$release_exists" == 0 || "$release_draft" == true ]]; then
    gh release edit "$tag" --repo "$RELEASES_REPOSITORY" --draft=false --latest=false
  fi
  exit 0
fi
[[ "$source_only_release" == 0 ]] || { echo 'Published source-only release cannot gain binary assets; use a new version' >&2; exit 1; }
if [[ "$PUBLISH_EXTERNAL_TAP" == true && -n "${TAP_SSH_PRIVATE_KEY:-}" ]]; then
  (umask 077; printf '%s\n' "$TAP_SSH_PRIVATE_KEY" > "$work/tap_key")
  gh api meta --jq '.ssh_keys[]' | sed 's/^/github.com /' > "$work/known_hosts"
  [[ -s "$work/known_hosts" ]] || { echo 'GitHub SSH host keys are unavailable' >&2; exit 1; }
  shell_quote() { local value=${1//\'/\'"\'"\'}; printf "'%s'" "$value"; }
  tap_ssh_command="ssh -F /dev/null -i $(shell_quote "$work/tap_key") -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$(shell_quote "$work/known_hosts")"
fi
cp "build/release/$asset" "build/release/$feed" "build/release/${token}.rb" build/release/sha256.txt "$work/"
if [[ "$release_exists" == 0 ]]; then
  release_args=(--repo "$RELEASES_REPOSITORY" --draft --title "HyperMug ${VERSION}" --notes "HyperMug ${CHANNEL} ${VERSION}; source ${GITHUB_SHA}")
  if [[ "$CHANNEL" == canary ]]; then release_args+=(--prerelease); fi

  gh release create "$tag" "$work/$asset" "$work/$feed" "$work/${token}.rb" "$work/sha256.txt" "${release_args[@]}"
else
  # Never regenerate a signed ZIP or its metadata on retry. Any missing asset
  # fails closed; gh release upload --clobber is deliberately absent.
  for name in "$asset" "$feed" "${token}.rb" sha256.txt; do
    gh release download "$tag" --repo "$RELEASES_REPOSITORY" --pattern "$name" --dir "$work" >/dev/null
    test -s "$work/$name" || { echo "Release asset missing: $name" >&2; exit 1; }
  done
fi
actual="$(shasum -a 256 "$work/$asset" | awk '{print $1}')"
expected="$(tr -d '\n' < "$work/sha256.txt")"
[[ "$actual" == "$expected" ]] || { echo 'Published ZIP checksum mismatch' >&2; exit 1; }
# A release with uploaded assets may still be a private draft after an API
# failure. Publish it before either public channel pointer can reference it.
if [[ "$release_exists" == 0 || "$release_draft" == true ]]; then
  publish_args=(--repo "$RELEASES_REPOSITORY" --draft=false)
  if [[ "$CHANNEL" == canary ]]; then
    publish_args+=(--prerelease --latest=false)
  else
    publish_args+=(--latest)
  fi
  publish_args+=(--notes "HyperMug ${CHANNEL} ${VERSION}; source ${GITHUB_SHA}")
  gh release edit "$tag" "${publish_args[@]}"
fi

# Feed version determines whether this run advances a channel. A retry of the
# current version resumes the cask step; an older version fails closed.
git clone "https://x-access-token:${RELEASE_TOKEN}@github.com/${RELEASES_REPOSITORY}.git" "$work/releases" >/dev/null 2>&1
(
  cd "$work/releases"
  if git ls-remote --exit-code origin refs/heads/updates >/dev/null; then
    git fetch origin updates; git checkout -b updates origin/updates
  else
    git checkout --orphan updates
    git rm -rf . >/dev/null
  fi
  old_version=''; old_build=''
  if [[ -f "$feed" ]]; then
    state="$(python3 - "$feed" <<'PYXML'
import sys, xml.etree.ElementTree as ET
item = ET.parse(sys.argv[1]).getroot().find('./channel/item')
if item is None:
    raise SystemExit('appcast item missing')
print(item.findtext('title').removeprefix('HyperMug '))
print(item.findtext('{http://www.andymatuschak.org/xml-namespaces/sparkle}version'))
PYXML
)"
    old_version="$(printf '%s\n' "$state" | sed -n '1p')"
    old_build="$(printf '%s\n' "$state" | sed -n '2p')"
    [[ -n "$old_version" && -n "$old_build" ]] || { echo 'Existing appcast cannot be ordered' >&2; exit 1; }
  fi
  decision="$(python3 - "$CHANNEL" "$VERSION" "$BUILD_NUMBER" "$old_version" "$old_build" <<'PY'
import sys
from release_metadata import publication_decision
print(publication_decision(*sys.argv[1:]))
PY
)"
  printf '%s\n' "$decision" > "$work/decision"
  if [[ "$decision" == advance ]]; then
    cp "$work/$feed" "$feed"
    git add "$feed"
    git -c user.name='HyperMug release bot' -c user.email='actions@users.noreply.github.com' commit -m "Update ${CHANNEL} appcast to ${VERSION}"
    git push origin HEAD:updates
  fi
)
[[ "$(cat "$work/decision")" != archive ]] || { echo "Older production version cannot publish" >&2; exit 1; }
# The optional external tap pointer is updated only after the release asset and feed exist.
if [[ "$PUBLISH_EXTERNAL_TAP" == true ]]; then
if [[ -n "${TAP_SSH_PRIVATE_KEY:-}" ]]; then
  export GIT_SSH_COMMAND="$tap_ssh_command"
  tap_url="git@github.com:${TAP_REPOSITORY}.git"
else
  tap_url="https://x-access-token:${TAP_TOKEN}@github.com/${TAP_REPOSITORY}.git"
fi
git clone "$tap_url" "$work/tap" >/dev/null 2>&1
(
  cd "$work/tap"
  mkdir -p Casks
  if [[ -f "Casks/${token}.rb" ]] && cmp -s "$work/${token}.rb" "Casks/${token}.rb"; then exit 0; fi
  cp "$work/${token}.rb" "Casks/${token}.rb"
  git add "Casks/${token}.rb"
  git -c user.name='HyperMug release bot' -c user.email='actions@users.noreply.github.com' commit -m "Update ${token} to ${VERSION}"
  git push origin HEAD
)
fi
# The source repository is a protected tap. Propose its cask from the immutable
# published asset; a failed PR can be resumed without replaying earlier writes.
python3 scripts/publish_source_cask.py --channel "$CHANNEL" --version "$VERSION" \
  --repository "$SOURCE_REPOSITORY" --asset "$work/${token}.rb" --work "$work/source"
