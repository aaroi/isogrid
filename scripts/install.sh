#!/bin/zsh
# Builds Isogrid, installs it in /Applications and starts it. Run it again to update.
set -euo pipefail
cd "${0:A:h}/.."
scripts/make-signing-identity.sh
scripts/build.sh

app=/Applications/Isogrid.app
# A running copy would keep the old version alive and take the launch below.
if pkill -x Isogrid; then
  while pgrep -qx Isogrid; do sleep 0.1; done
fi
rm -rf "$app"
ditto build/Isogrid.app "$app"
open "$app"
echo "Installed $app. Turn Isogrid on in System Settings > Privacy & Security > Accessibility if macOS asks."
