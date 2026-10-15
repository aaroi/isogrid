#!/bin/zsh
# Swift Testing ships inside the Command Line Tools, outside the default search paths.
set -euo pipefail
cd "${0:A:h}/.."
frameworks=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
libs=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [[ -d $frameworks ]]; then
  swift test -Xswiftc -F$frameworks -Xlinker -F$frameworks \
    -Xlinker -rpath -Xlinker $frameworks -Xlinker -rpath -Xlinker $libs "$@"
else
  swift test "$@"
fi
