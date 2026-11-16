#!/usr/bin/env bash
# Creates the self-signed code-signing identity "HyperMug Local Signing" in the login keychain,
# so build.sh signs every build with the same identity and macOS keeps the app's
# Accessibility / Input Monitoring grants across rebuilds. Idempotent; needs no sudo.
set -euo pipefail

NAME="HyperMug Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Not `-v`: a self-signed identity is untrusted but valid for codesign.
if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "Signing identity \"$NAME\" already exists; nothing to do."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = $NAME

[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

pw="$(/usr/bin/openssl rand -hex 16)"

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$tmp/openssl.cnf" -subj "/CN=$NAME" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem"
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -name "$NAME" -out "$tmp/identity.p12" -passout "pass:$pw"

security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$pw" -T /usr/bin/codesign

if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "Created signing identity \"$NAME\" in the login keychain."
  echo "The first ./build.sh may ask once to let codesign use the key: choose Always Allow."
else
  echo "error: identity \"$NAME\" not found after import" >&2
  exit 1
fi
