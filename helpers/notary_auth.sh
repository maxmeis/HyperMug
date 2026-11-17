#!/usr/bin/env bash
# Sourced by release.sh after its temporary directory has been created.
configure_notary_auth() {
  local work_dir="$1"
  : "${APP_STORE_CONNECT_PRIVATE_KEY:?}" "${APP_STORE_CONNECT_KEY_ID:?}" "${APP_STORE_CONNECT_ISSUER_ID:?}"
  NOTARY_KEY_FILE="$work_dir/app-store-connect-key.p8"
  printf '%s' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$NOTARY_KEY_FILE"
  NOTARY_AUTH_ARGS=(--key "$NOTARY_KEY_FILE" --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID")
}

submit_for_notarization() {
  xcrun notarytool submit "$1" "${NOTARY_AUTH_ARGS[@]}" --wait --output-format json
}
