#!/bin/zsh
# Creates a self-signed "Isogrid Local Signing" code-signing identity in the login keychain.
# macOS ties Accessibility access to the code signature; signing every build with this identity
# keeps the grant across rebuilds. The PKCS#12 password below only protects a temporary file
# that is deleted when the script exits.
set -euo pipefail
dir=$(mktemp -d)
trap 'rm -rf $dir' EXIT
cat > $dir/cert.cnf <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Isogrid Local Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout $dir/key.pem -out $dir/cert.pem -days 3650 -config $dir/cert.cnf
/usr/bin/openssl pkcs12 -export -inkey $dir/key.pem -in $dir/cert.pem -out $dir/id.p12 -passout pass:isogrid -name "Isogrid Local Signing"
security import $dir/id.p12 -k ~/Library/Keychains/login.keychain-db -P isogrid -T /usr/bin/codesign
