#!/usr/bin/env bash

# Configure and submit a notarytool request. This file is sourced by release.sh.
configure_notary_auth() {
  local work_dir="$1"
  local has_api_config=0

  if [[ -n "${APP_STORE_CONNECT_PRIVATE_KEY:-}" || -n "${APP_STORE_CONNECT_KEY_ID:-}" || -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
    has_api_config=1
  fi

  if [[ "$has_api_config" == 1 ]]; then
    [[ -n "${APP_STORE_CONNECT_PRIVATE_KEY:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]] || {
      echo 'Incomplete App Store Connect API notarization credentials' >&2
      return 1
    }
    NOTARY_KEY_FILE="$work_dir/app-store-connect-key.p8"
    printf '%s' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$NOTARY_KEY_FILE"
    NOTARY_AUTH_ARGS=(--key "$NOTARY_KEY_FILE" --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID")
  else
    [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]] || {
      echo 'Missing Apple app-specific password notarization credentials' >&2
      return 1
    }
    NOTARY_KEY_FILE=''
    NOTARY_AUTH_ARGS=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
  fi
}

submit_for_notarization() {
  xcrun notarytool submit "$1" "${NOTARY_AUTH_ARGS[@]}" --wait
}
