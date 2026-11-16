#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Keep local and PR builds independent of a caller's release environment.
exec env -u SIGN_KEYCHAIN -u SPARKLE_PUBLIC_ED_KEY -u APPCAST_URL \
  -u RELEASES_REPOSITORY -u APP_VERSION -u BUILD_NUMBER -u RELEASE_CHANNEL \
  SIGN_ID=- REQUIRE_SIGNING=0 "$script_dir/../build.sh" "$@"
