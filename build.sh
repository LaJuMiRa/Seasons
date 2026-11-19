#!/usr/bin/env bash
# Builds build/Seasons.app (arm64, ad-hoc signed). Needs only the Xcode Command Line Tools.
#
#   ./build.sh            release build, version from the VERSION file
#   VERSION=1.2.3 ./build.sh
#
# The app is assembled and signed in a temporary folder and copied to build/ afterwards:
# folders synced by iCloud Drive add Finder metadata that makes `codesign` fail.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
WORK="${SEASONS_WORK_DIR:-${TMPDIR:-/tmp}/seasons-build}"
SCRATCH="$WORK/spm"
STAGE="$WORK/stage"
APP_NAME="Seasons.app"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: VERSION must look like 1.2.3 (got '$VERSION')" >&2
    exit 1
fi

echo "==> Building Seasons $VERSION ($BUILD_NUMBER) for arm64"
swift build -c release --arch arm64 --scratch-path "$SCRATCH"
BIN_DIR="$(swift build -c release --arch arm64 --scratch-path "$SCRATCH" --show-bin-path)"

echo "==> Assembling app bundle"
rm -rf "$STAGE"
CONTENTS="$STAGE/$APP_NAME/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/Seasons" "$CONTENTS/MacOS/Seasons"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" packaging/Info.plist > "$CONTENTS/Info.plist"
plutil -lint -s "$CONTENTS/Info.plist"
cp -R Sources/Seasons/Resources/*.lproj "$CONTENTS/Resources/"

echo "==> Drawing app icon"
ICON_TOOL="$WORK/make-icon"
if [[ ! -x "$ICON_TOOL" || scripts/make-icon.swift -nt "$ICON_TOOL" ]]; then
    swiftc -O scripts/make-icon.swift -o "$ICON_TOOL"
fi
rm -rf "$WORK/AppIcon.iconset"
"$ICON_TOOL" "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
xattr -cr "$STAGE/$APP_NAME"
codesign --force --sign - --options runtime --timestamp=none "$STAGE/$APP_NAME"
codesign --verify --strict --verbose=1 "$STAGE/$APP_NAME"

echo "==> Copying to build/"
mkdir -p "$ROOT/build"
rm -rf "$ROOT/build/$APP_NAME"
ditto "$STAGE/$APP_NAME" "$ROOT/build/$APP_NAME"
echo "Done: build/$APP_NAME"
