#!/bin/sh
# Build a release binary and install it as `mac-cleaner` on your PATH.
# Builds outside this iCloud-synced folder, and copies the binary rather than linking it,
# so cleaning ~/Library/Caches can't break the installed command.
set -e
cd "$(dirname "$0")"
scratch="$HOME/Library/Caches/MacCleaner/spm"
dest="${1:-$HOME/.local/bin}"
swift build -c release --scratch-path "$scratch"
mkdir -p "$dest"
cp "$scratch/release/mac-cleaner" "$dest/mac-cleaner"
echo "Installed $dest/mac-cleaner"
case ":$PATH:" in *":$dest:"*) ;; *) echo "Note: $dest is not on your PATH." ;; esac
