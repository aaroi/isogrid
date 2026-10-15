#!/bin/zsh
# End-to-end test against real windows. Opens throwaway test windows for about 20 seconds and
# drives a separate test instance of Isogrid, which leaves your own windows and sets alone.
set -euo pipefail
cd "${0:A:h}/.."
scripts/build.sh >/dev/null
swift build --product IsogridFixture >/dev/null
swift build --product isogrid-e2e >/dev/null
bin=$(swift build --show-bin-path)
"$bin/isogrid-e2e" "$PWD/build/Isogrid.app" "$bin/IsogridFixture"
