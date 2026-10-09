#!/bin/bash
# Packs build/Free Buds Manager.app into dist/FreeBudsManager-<version>.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
APP="build/Free Buds Manager.app"
STAGE="build/dmg"
OUT="dist/FreeBudsManager-$VERSION.dmg"

[ -d "$APP" ] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }

rm -rf "$STAGE" && mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
cp Resources/dmg-readme.txt "$STAGE/READ ME FIRST.txt"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "Free Buds Manager" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
rm -rf "$STAGE"   # keep a second copy of the app out of Spotlight
echo "Created $OUT"
