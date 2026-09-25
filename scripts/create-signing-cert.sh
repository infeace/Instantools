#!/usr/bin/env bash
# Creates a self-signed code signing identity in the login keychain, once per machine.
# Every build signed with it has the same designated requirement, so Accessibility and
# Input Monitoring grants survive rebuilds. macOS asks for your password to trust it.
set -euo pipefail

name="Instantools Local Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"
# The system LibreSSL writes PKCS12 files that `security import` accepts without -legacy.
openssl=/usr/bin/openssl

if grep -q "\"$name\"" <<<"$(security find-identity -v -p codesigning)"; then
    echo "'$name' already exists, nothing to do."
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/cert.conf" <<EOF
[ req ]
distinguished_name = req_name
prompt = no
[ req_name ]
CN = $name
[ extensions ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

password="$(uuidgen)"
"$openssl" req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -config "$tmp/cert.conf" -extensions extensions \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem"
"$openssl" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -name "$name" -out "$tmp/cert.p12" -passout "pass:$password"

security import "$tmp/cert.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$tmp/cert.pem"

security find-identity -v -p codesigning | grep "\"$name\""
echo "Created '$name'. Rebuild with scripts/build.sh."
