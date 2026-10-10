#!/bin/bash
# Builds the Swift package and wraps the binary in an .app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

# Pass "release" for a build to use day to day; the debug build adds snapshot/demo flags.
# A release build is universal (Apple silicon and Intel); a debug build is for this Mac only.
CONFIG="${1:-debug}"
ARCHS=()
if [[ "$CONFIG" == "release" ]]; then
    ARCHS=(arm64 x86_64)
    for arch in "${ARCHS[@]}"; do
        swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path ".build-$arch"
    done
else
    swift build -c "$CONFIG"
    BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
fi
# Puts a built product into the bundle, joining the architectures of a release build.
place() {
    if (( ${#ARCHS[@]} )); then
        local parts=()
        for arch in "${ARCHS[@]}"; do
            parts+=("$(swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path ".build-$arch" --show-bin-path)/$1")
        done
        lipo -create "${parts[@]}" -output "$2/$1"
        lipo "$2/$1" -verify_arch "${ARCHS[@]}"
    else
        cp "$BIN_DIR/$1" "$2/$1"
    fi
}

# Assemble and sign outside the project folder: a synced folder (iCloud Desktop) keeps adding
# Finder info to the bundle, which a certificate signature rejects.
WORK="$(mktemp -d)"
APP="$WORK/Nunsseop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
place Nunsseop "$APP/Contents/MacOS"
place libNowPlayingHelper.dylib "$APP/Contents/Resources"
cp Resources/nowplaying.pl "$APP/Contents/Resources/"
cp -R Resources/*.lproj Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
# A fixed certificate keeps the code requirement stable, so macOS keeps the Accessibility
# permission across updates. Without it, sign ad hoc.
IDENTITY="${CODESIGN_IDENTITY:-Nunsseop Code Signing}"
security find-certificate -c "$IDENTITY" >/dev/null 2>&1 || IDENTITY="-"
codesign --force --sign "$IDENTITY" "$APP/Contents/Resources/libNowPlayingHelper.dylib" >/dev/null
codesign --force --sign "$IDENTITY" "$APP" >/dev/null
rm -rf build/Nunsseop.app
mkdir -p build
ditto "$APP" build/Nunsseop.app
rm -rf "$WORK"
echo build/Nunsseop.app
