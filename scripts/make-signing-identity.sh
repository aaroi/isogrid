#!/bin/zsh
# Creates the self-signed "Isogrid Local Signing" identity, unless it exists. macOS ties
# Accessibility access to the code signature, so signing every build with one identity keeps
# the grant across rebuilds.
# The identity lives in a keychain of its own with a fixed password, so scripts/build.sh can
# unlock it and sign without a password prompt. The login keychain is left alone.
set -euo pipefail
keychain=~/Library/Keychains/isogrid.keychain-db
name="Isogrid Local Signing"
if [[ -f $keychain ]]; then
  echo "$name already exists"
  exit 0
fi
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cat > "$dir/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$dir/key.pem" -out "$dir/cert.pem" -days 3650 \
  -config "$dir/cert.cnf"
/usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -out "$dir/id.p12" -passout pass:isogrid -name "$name"
# Built aside and moved into place last, so a failed run leaves nothing half made.
security create-keychain -p isogrid "$dir/isogrid.keychain-db"
security set-keychain-settings "$dir/isogrid.keychain-db"
security import "$dir/id.p12" -k "$dir/isogrid.keychain-db" -P isogrid -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k isogrid "$dir/isogrid.keychain-db" >/dev/null
mv "$dir/isogrid.keychain-db" "$keychain"
echo "Created $name in $keychain"
