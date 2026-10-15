#!/bin/zsh
# Builds build/Isogrid.app. macOS ties the Accessibility grant to the signature, so signing
# with the same identity every build keeps it. scripts/make-signing-identity.sh creates a
# local one; without it the app is signed ad hoc and macOS asks again after every build.
# ISOGRID_SIGN_IDENTITY signs with another identity, such as a Developer ID.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
app=build/Isogrid.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Isogrid" "$app/Contents/MacOS/Isogrid"
cp Support/Info.plist "$app/Contents/Info.plist"
cp Support/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
identity=${ISOGRID_SIGN_IDENTITY:-}
keychain=~/Library/Keychains/isogrid.keychain-db
if [[ -z $identity && -f $keychain ]]; then
  # codesign only looks in the keychain search list, so the Isogrid keychain joins it while signing.
  keychains=("${(@f)$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')}")
  trap 'security list-keychains -d user -s "${keychains[@]}"' EXIT
  security list-keychains -d user -s "${keychains[@]}" "$keychain"
  security unlock-keychain -p isogrid "$keychain"
  identity=$(security find-identity -p codesigning "$keychain" | awk '/Isogrid Local Signing/ { print $2; exit }')
fi
codesign --force --options runtime --sign "${identity:--}" "$app"
echo "Built $app"
