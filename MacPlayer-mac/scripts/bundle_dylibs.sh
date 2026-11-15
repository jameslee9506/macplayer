#!/bin/zsh
# Prepare and verify the app's Homebrew libraries without modifying the originals.
set -euo pipefail
exec /usr/bin/python3 "${0:A:h}/bundle_dylibs.py" "$@"
