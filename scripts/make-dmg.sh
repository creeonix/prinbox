#!/usr/bin/env bash
# Packs an app bundle into a compressed, read-only DMG with an Applications shortcut, and writes a
# SHA-256 checksum next to it.
# Usage: scripts/make-dmg.sh <App.app> <output.dmg> <volume name>
set -euo pipefail

app=${1:?usage: scripts/make-dmg.sh <App.app> <output.dmg> <volume name>}
dmg=${2:?usage: scripts/make-dmg.sh <App.app> <output.dmg> <volume name>}
volume=${3:?usage: scripts/make-dmg.sh <App.app> <output.dmg> <volume name>}

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

rm -f "$dmg" "$dmg.sha256"
hdiutil create -volname "$volume" -srcfolder "$staging" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$dmg" >/dev/null
(cd "$(dirname "$dmg")" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
echo "wrote $dmg"
