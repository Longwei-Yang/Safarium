#!/bin/zsh
# Create the fixed self-signed code signing identity package-safarium.sh signs
# Safarium with, in its own keychain (the login keychain is not touched):
#   ~/chromium/signing/safarium-signing.keychain-db  + keychain-password
# Run once per build machine and keep that folder (back it up): builds signed
# with a new certificate make macOS ask for keychain access once more.
# The certificate isn't trusted by the system; it doesn't need to be.
set -euo pipefail
DIR=${SAFARIUM_SIGNING_DIR:-$HOME/chromium/signing}
KEYCHAIN=$DIR/safarium-signing.keychain-db
[[ -e $KEYCHAIN ]] && { echo "$KEYCHAIN already exists"; exit 1; }
mkdir -p "$DIR"; chmod 700 "$DIR"; umask 077
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
/usr/bin/openssl rand -base64 24 | tr -d '\n' > "$DIR/keychain-password"
cat > "$TMP/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Safarium Code Signing
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$DIR/cert.pem" 2>/dev/null
P12=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$DIR/cert.pem" \
  -name "Safarium Code Signing" -out "$TMP/identity.p12" -passout "pass:$P12"
PW=$(<"$DIR/keychain-password")
security create-keychain -p "$PW" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # no auto-lock
security unlock-keychain -p "$PW" "$KEYCHAIN"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KEYCHAIN" >/dev/null
security find-identity -p codesigning "$KEYCHAIN" | grep 'Safarium Code Signing'
