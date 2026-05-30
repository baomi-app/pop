#!/bin/bash
# One-time: create a stable self-signed code-signing identity in a dedicated keychain.
# Signing Pop with this identity (see dev-install.sh) gives it a constant designated
# requirement, so macOS keeps Screen Recording (TCC) permission across rebuilds.
# Re-run only if the identity is missing. The keychain password is local-dev only.
set -euo pipefail

NAME="Pop Dev Self Signed"
KC="$HOME/Library/Keychains/pop-signing.keychain-db"
PW="pop"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/k.key" -out "$TMP/c.crt" \
    -days 3650 -nodes -config "$TMP/cnf"
# Legacy PBE/MAC so macOS `security` can parse the PKCS#12 (OpenSSL 3 defaults can't).
openssl pkcs12 -export -legacy -inkey "$TMP/k.key" -in "$TMP/c.crt" \
    -out "$TMP/i.p12" -passout pass:pop -name "$NAME" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$PW" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$PW" "$KC"
security import "$TMP/i.p12" -k "$KC" -P pop -T /usr/bin/codesign -A
security set-key-partition-list -S apple-tool:,apple: -s -k "$PW" "$KC" >/dev/null 2>&1 || true
EXISTING=$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')
security list-keychains -d user -s "$KC" $EXISTING

echo "✓ Identity ready:"
security find-identity -p codesigning "$KC" | grep "$NAME" || true
