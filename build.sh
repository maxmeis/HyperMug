#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/Source/HyperMug"
exec ./build.sh "$@"
