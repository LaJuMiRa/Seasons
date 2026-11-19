#!/usr/bin/env bash
# Builds the app and packages dist/Seasons-<version>-arm64.zip plus its SHA-256.
#
#   ./release.sh            version from the VERSION file
#   VERSION=1.2.3 ./release.sh
#
# Used locally and by .github/workflows/release.yml.
set -euo pipefail

cd "$(dirname "$0")"
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
export VERSION
WORK="${SEASONS_WORK_DIR:-${TMPDIR:-/tmp}/seasons-build}"
export SEASONS_WORK_DIR="$WORK"

./build.sh

mkdir -p dist
ZIP="dist/Seasons-$VERSION-arm64.zip"
rm -f "$ZIP" "$ZIP.sha256"
# Zip the clean staging copy (build/ may carry iCloud metadata) without extended attributes.
ditto -c -k --norsrc --noextattr --keepParent "$WORK/stage/Seasons.app" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "$SHA  $(basename "$ZIP")" > "$ZIP.sha256"

echo "==> $ZIP"
echo "    sha256: $SHA"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "zip=$ZIP"
        echo "sha256=$SHA"
    } >> "$GITHUB_OUTPUT"
fi
