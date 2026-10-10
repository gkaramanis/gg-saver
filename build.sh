#!/bin/bash
# Builds gg.saver.saver for Apple silicon and Intel with the Xcode command line tools.
# ./build.sh --install also copies it to ~/Library/Screen Savers.
set -euo pipefail
cd "$(dirname "$0")"

NAME=GGSaver
OUT=build/gg.saver.saver
SDK=$(xcrun --sdk macosx --show-sdk-path)

rm -rf build
mkdir -p "$OUT/Contents/MacOS" build/obj

for arch in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -sdk "$SDK" -target "$arch-apple-macos14.0" \
    -module-name "$NAME" -emit-library \
    -framework ScreenSaver -framework SpriteKit -framework AppKit \
    -o "build/obj/$NAME-$arch" GGSaver/*.swift
done

lipo -create build/obj/$NAME-* -output "$OUT/Contents/MacOS/$NAME"
cp GGSaver/Info.plist "$OUT/Contents/Info.plist"
mkdir -p "$OUT/Contents/Resources"
cp GGSaver/Resources/* "$OUT/Contents/Resources/"
codesign --force --sign - "$OUT"
echo "Built $OUT"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Library/Screen Savers"
  mkdir -p "$DEST"
  rm -rf "$DEST/gg.saver.saver"
  cp -R "$OUT" "$DEST/"
  # The running host keeps the old copy loaded until it quits.
  killall legacyScreenSaver 2>/dev/null || true
  echo "Installed. Pick gg.saver in System Settings → Screen Saver."
fi
