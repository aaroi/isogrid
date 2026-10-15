#!/bin/zsh
# The Command Line Tools ship Swift Testing outside the default search paths, so the build is
# pointed at it there. With Xcode selected, plain `swift test` finds it.
set -euo pipefail
cd "${0:A:h}/.."
developer=$(xcode-select -p)
if [[ $developer == */CommandLineTools ]]; then
  frameworks=$developer/Library/Developer/Frameworks
  libs=$developer/Library/Developer/usr/lib
  swift test -Xswiftc -F$frameworks -Xlinker -F$frameworks \
    -Xlinker -rpath -Xlinker $frameworks -Xlinker -rpath -Xlinker $libs "$@"
else
  swift test "$@"
fi
