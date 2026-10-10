#!/bin/bash
# Checks the DMG that is about to ship: the app inside has this version, runs on Apple silicon and Intel,
# has an intact signature, and starts. Starting it quits a running Nunsseop and reopens it afterwards.
#
#   scripts/check-dmg.sh build/Nunsseop-<version>.dmg <version>
set -euo pipefail
cd "$(dirname "$0")/.."

DMG="${1:?usage: scripts/check-dmg.sh <dmg> <version>}"
VERSION="${2:?usage: scripts/check-dmg.sh <dmg> <version>}"
step() { echo "▸ $*" >&2; }
fail() { echo "✘ $*" >&2; exit 1; }

WORK="$(mktemp -d)"
MOUNT="$WORK/mount"
RUNNING=0
cleanup() {
    pkill -f "$WORK/Nunsseop.app/Contents/MacOS/Nunsseop" 2>/dev/null || true
    hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
    rm -rf "$WORK"
    if (( RUNNING )); then open -a /Applications/Nunsseop.app || true; fi
}
trap cleanup EXIT

step "Mount"
mkdir -p "$MOUNT"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
APP="$MOUNT/Nunsseop.app"
[[ -d "$APP" ]] || fail "No Nunsseop.app in the DMG"
[[ -L "$MOUNT/Applications" ]] || fail "No Applications link in the DMG"

step "Version $VERSION"
SHIPPED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$SHIPPED" == "$VERSION" ]] || fail "The app says $SHIPPED"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == "io.github.namekun.Nunsseop" ]] \
    || fail "Unexpected bundle identifier"

step "Apple silicon and Intel"
for binary in Contents/MacOS/Nunsseop Contents/Resources/libNowPlayingHelper.dylib; do
    lipo "$APP/$binary" -verify_arch arm64 x86_64 || fail "$binary is $(lipo -archs "$APP/$binary") only"
done

step "Signature"
codesign --verify --deep --strict "$APP" || fail "Signature is broken"

step "Resources"
for item in Contents/Resources/nowplaying.pl Contents/Resources/AppIcon.icns Contents/Resources/en.lproj Contents/Resources/ko.lproj; do
    [[ -e "$APP/$item" ]] || fail "Missing $item"
done

step "It starts and answers on its local port"
if pgrep -x Nunsseop >/dev/null; then
    RUNNING=1
    osascript -e 'quit app "Nunsseop"' >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do pgrep -x Nunsseop >/dev/null || break; sleep 0.25; done
    pkill -x Nunsseop 2>/dev/null || true
fi
ditto "$APP" "$WORK/Nunsseop.app"
"$WORK/Nunsseop.app/Contents/MacOS/Nunsseop" >"$WORK/run.log" 2>&1 &
PID=$!
sleep 6
kill -0 "$PID" 2>/dev/null || { tail -20 "$WORK/run.log" >&2; fail "It quit within 6 seconds"; }
# No token: the server is up and refuses it.
CODE="$(curl -s -o /dev/null -w '%{http_code}' -m 2 -X POST http://127.0.0.1:47750/notify -d '{}' || true)"
[[ "$CODE" == "401" ]] || fail "The local port answered '$CODE' instead of 401"
kill "$PID"; wait "$PID" 2>/dev/null || true

echo "✔ $DMG is ready to ship" >&2
