#!/bin/sh
# Builds gg.saver.saver for Apple silicon and Intel.
# Usage: build.sh [install | release | pkg]. "release" notarizes the saver and zips it;
# "pkg" does the same and also builds a signed, notarized installer package.
# Notarizing uses the keychain profile in NOTARY_PROFILE (default: stripes-notary).
set -eu
cd "$(dirname "$0")"

NAME=GGSaver
out=build/gg.saver.saver
identity_app="Developer ID Application: Georgios Karamanis (N4B5PD6UN5)"
identity_pkg="Developer ID Installer: Georgios Karamanis (N4B5PD6UN5)"
profile=${NOTARY_PROFILE:-stripes-notary}

rm -rf build
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources" build/obj

# The Command Line Tools lack the Intel slice of a Swift support library; a full Xcode has it.
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcode-select -p | grep -q '\.app/'; then
    for x in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [ -d "$x" ]; then export DEVELOPER_DIR="$x/Contents/Developer"; break; fi
    done
fi
SDK=$(xcrun --sdk macosx --show-sdk-path)

for arch in arm64 x86_64; do
    xcrun swiftc -O -swift-version 5 -sdk "$SDK" -target "$arch-apple-macos14.0" \
        -module-name "$NAME" -emit-library \
        -framework ScreenSaver -framework SpriteKit -framework AppKit \
        -o "build/obj/$NAME-$arch" GGSaver/*.swift
done
lipo -create build/obj/$NAME-* -output "$out/Contents/MacOS/$NAME"
cp GGSaver/Info.plist "$out/Contents/Info.plist"

# System Settings reads the thumbnail only from a TIFF holding both resolutions.
# tools/thumbnail.sh redraws the PNGs.
tiffutil -cathidpicheck GGSaver/Resources/thumbnail.png GGSaver/Resources/thumbnail@2x.png \
    -out "$out/Contents/Resources/thumbnail.tiff" >/dev/null

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' GGSaver/Info.plist)
id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' GGSaver/Info.plist)

if [ "${1:-}" = release ] || [ "${1:-}" = pkg ]; then
    codesign --force --options runtime --timestamp --sign "$identity_app" "$out"

    # notarytool needs an archive; the stapled bundle is zipped again for release.
    zip="build/gg.saver-$version.zip"
    ditto -c -k --keepParent "$out" "$zip"
    xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
    xcrun stapler staple "$out"
    rm "$zip"
    ditto -c -k --keepParent "$out" "$zip"
    xcrun stapler validate "$out"
    echo "Notarized: $zip"
else
    codesign --force --sign - "$out"
    echo "Built $out"
fi

if [ "${1:-}" = pkg ]; then
    work=build/pkg
    mkdir -p "$work/root"
    ditto "$out" "$work/root/gg.saver.saver"

    # Not relocatable, so the installer never writes over a copy it finds somewhere else.
    pkgbuild --analyze --root "$work/root" "$work/component.plist" >/dev/null
    plutil -replace 0.BundleIsRelocatable -bool NO "$work/component.plist"
    mkdir -p "$work/scripts"
    cp pkg/postinstall "$work/scripts/"
    chmod +x "$work/scripts/postinstall"
    pkgbuild --root "$work/root" --component-plist "$work/component.plist" \
        --scripts "$work/scripts" --identifier "$id" --version "$version" \
        --install-location "/Library/Screen Savers" "$work/gg.saver.pkg"

    # The user picks this Mac or only their own account; the second needs no admin password.
    cat > "$work/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>gg.saver</title>
    <domains enable_anywhere="false" enable_currentUserHome="true" enable_localSystem="true"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
    <choices-outline><line choice="default"/></choices-outline>
    <choice id="default" title="gg.saver"><pkg-ref id="$id"/></choice>
    <pkg-ref id="$id" version="$version">gg.saver.pkg</pkg-ref>
</installer-gui-script>
EOF

    pkg="build/gg.saver-$version.pkg"
    productbuild --distribution "$work/distribution.xml" --package-path "$work" \
        --sign "$identity_pkg" --timestamp "$pkg"
    rm -rf "$work"
    xcrun notarytool submit "$pkg" --keychain-profile "$profile" --wait
    xcrun stapler staple "$pkg"
    spctl -a -vv -t install "$pkg"
    echo "Notarized: $pkg"
fi

if [ "${1:-}" = install ] || [ "${1:-}" = --install ]; then
    dest="$HOME/Library/Screen Savers/gg.saver.saver"
    [ -e "$dest" ] && trash "$dest"
    mkdir -p "$HOME/Library/Screen Savers"
    cp -R "$out" "$dest"

    # The saver host caches the old bundle until it restarts.
    killall legacyScreenSaver 2>/dev/null || true
    echo "Installed to $dest"
fi
