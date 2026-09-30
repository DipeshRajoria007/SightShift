#!/bin/bash
# Signs SightShift.app with a stable, self-signed local identity.
#
# macOS remembers Camera and Accessibility permissions by code signature. An ad-hoc signature
# changes with every build, so macOS would forget both permissions after each rebuild. A
# self-signed certificate keeps the signature's identity stable, the same way yabai and other
# open-source tools handle it.
#
# The certificate lives in its own keychain under .signing/ (git-ignored). It is only added to
# your keychain search list for the moment codesign needs it; your login keychain is never
# touched. Set SIGN_IDENTITY to sign with a real identity instead, or SIGN_IDENTITY=- for ad hoc.
set -euo pipefail

APP="${1:?usage: sign.sh path/to/SightShift.app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT/App/SightShift.entitlements"
SIGNING_DIR="$ROOT/.signing"
KEYCHAIN="$SIGNING_DIR/sightshift.keychain-db"
PASSWORD="sightshift-local-signing"
NAME="SightShift Local Signing"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" --timestamp=none "$APP"
  exit 0
fi

ORIGINAL_KEYCHAINS=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%\"}"
  line="${line#\"}"
  [[ -n "$line" ]] && ORIGINAL_KEYCHAINS+=("$line")
done < <(security list-keychains -d user)

restore_search_list() {
  security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"
}
trap restore_search_list EXIT

create_identity() {
  echo "Creating a local signing identity in $SIGNING_DIR (one time)…"
  mkdir -p "$SIGNING_DIR"
  local tmp
  tmp="$(mktemp -d)"
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
  # The system LibreSSL writes a PKCS#12 file the keychain can import.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
    -days 3650 -config "$tmp/openssl.cnf" >/dev/null 2>&1
  /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/identity.p12" \
    -passout "pass:$PASSWORD" -name "$NAME" >/dev/null 2>&1
  rm -f "$KEYCHAIN"
  security create-keychain -p "$PASSWORD" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"
  security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
  security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign -f pkcs12 >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
  rm -rf "$tmp"
  restore_search_list
}

identity_hash() {
  security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | awk -v name="\"$NAME\"" 'index($0, name) { print $2; exit }'
}

if [[ ! -f "$KEYCHAIN" ]] || [[ -z "$(identity_hash)" ]]; then
  create_identity || true
fi

HASH="$(identity_hash || true)"
if [[ -z "$HASH" ]]; then
  echo "warning: no local signing identity; signing ad hoc (macOS will ask for permissions again after each rebuild)" >&2
  codesign --force --sign - --entitlements "$ENTITLEMENTS" --timestamp=none "$APP"
  exit 0
fi

security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
codesign --force --sign "$HASH" --entitlements "$ENTITLEMENTS" --timestamp=none "$APP"
echo "Signed $(basename "$APP") with \"$NAME\""
