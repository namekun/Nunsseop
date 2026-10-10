#!/bin/bash
# Releases a new version: runs every check (scripts/preflight.sh), bumps the version, builds the DMG and checks
# it (scripts/check-dmg.sh), and only then commits, tags, publishes the GitHub release and updates the Homebrew tap.
#
#   scripts/release.sh <version> [notes-file]
#
# Notes come from the file, or from $EDITOR when no file is given. The tap repo is expected at
# ../homebrew-tap (override with TAP_DIR).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [notes-file]}"
NOTES_FILE="${2:-}"
TAP_DIR="${TAP_DIR:-../homebrew-tap}"
CASK="$TAP_DIR/Casks/nunsseop.rb"
PLIST="Resources/Info.plist"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must look like 1.2.3" >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "Release from main" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree is not clean" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "v$VERSION already exists" >&2; exit 1; }
[[ -f "$CASK" ]] || { echo "Homebrew tap not found at $TAP_DIR" >&2; exit 1; }

if [[ -z "$NOTES_FILE" ]]; then
    NOTES_FILE="$(mktemp)"
    "${EDITOR:-vi}" "$NOTES_FILE"
fi
[[ -s "$NOTES_FILE" ]] || { echo "Release notes are empty" >&2; exit 1; }

./scripts/preflight.sh

# Until the version commit is pushed, a failure puts the bumped files back.
PUSHED=0
trap '(( PUSHED )) || git checkout -q -- "$PLIST" docs/index.html' EXIT

OLD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST") + 1 ))"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$PLIST"
sed -i '' "s|<b>v$OLD_VERSION</b>|<b>v$VERSION</b>|" docs/index.html
grep -q "<b>v$VERSION</b>" docs/index.html || { echo "The site's version badge wasn't updated" >&2; exit 1; }

DMG="$(./scripts/make-dmg.sh)"
./scripts/check-dmg.sh "$DMG" "$VERSION"

git add "$PLIST" docs/index.html
git commit -q -m "Version $VERSION"
git tag "v$VERSION"
git push -q origin main "v$VERSION"
PUSHED=1

gh release create "v$VERSION" "$DMG" --title "v$VERSION" --notes-file "$NOTES_FILE"

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
git -C "$TAP_DIR" pull -q --ff-only
sed -i '' -e "s/version \"[0-9.]*\"/version \"$VERSION\"/" -e "s/sha256 \"[0-9a-f]*\"/sha256 \"$SHA\"/" "$CASK"
grep -q "version \"$VERSION\"" "$CASK" && grep -q "sha256 \"$SHA\"" "$CASK" \
    || { echo "The cask wasn't updated; fix $CASK by hand" >&2; exit 1; }
git -C "$TAP_DIR" commit -qam "nunsseop $VERSION"
git -C "$TAP_DIR" push -q

# The download must match what the cask promises.
PUBLISHED="$(curl -sL "https://github.com/namekun/Nunsseop/releases/download/v$VERSION/$(basename "$DMG")" | shasum -a 256 | cut -d' ' -f1)"
[[ "$PUBLISHED" == "$SHA" ]] || { echo "Published DMG checksum $PUBLISHED does not match $SHA" >&2; exit 1; }
echo "Released v$VERSION ($DMG, sha256 $SHA)"
