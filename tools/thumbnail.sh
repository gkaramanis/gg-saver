#!/bin/sh
# Writes GGSaver/Resources/thumbnail.png and thumbnail@2x.png from a Lava lamp frame.
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
# Top-level code is allowed only in main.swift.
cp tools/thumbnail.swift "$tmp/main.swift"
xcrun swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework ScreenSaver -framework SpriteKit -framework AppKit \
    -o "$tmp/thumbnail" GGSaver/*.swift "$tmp/main.swift"
"$tmp/thumbnail" "$tmp/frame.png"
sips -z 58 90 "$tmp/frame.png" --out GGSaver/Resources/thumbnail.png >/dev/null
sips -z 116 180 "$tmp/frame.png" --out GGSaver/Resources/thumbnail@2x.png >/dev/null
rm -rf "$tmp"
echo "Wrote GGSaver/Resources/thumbnail.png and thumbnail@2x.png"
