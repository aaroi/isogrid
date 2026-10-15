#!/bin/zsh
# Builds build/Isogrid.app. macOS ties the Accessibility grant to the signature, so signing
# with the same identity every build keeps it. scripts/make-signing-identity.sh creates a
# local one; without it the app is signed ad hoc and macOS asks again after every build.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --arch arm64
app=build/Isogrid.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/arm64-apple-macosx/release/Isogrid "$app/Contents/MacOS/Isogrid"
cp Support/Info.plist "$app/Contents/Info.plist"
identity=${ISOGRID_SIGN_IDENTITY:-}
if [[ -z $identity ]] && security find-identity -p codesigning | grep -q "Isogrid Local Signing"; then
  identity="Isogrid Local Signing"
fi
codesign --force --options runtime --sign "${identity:--}" "$app"
echo "Built $app"
