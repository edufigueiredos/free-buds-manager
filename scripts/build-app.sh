#!/bin/bash
# Builds build/Free Buds Manager.app (universal, ad-hoc signed unless SIGN_IDENTITY is set).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
APP="build/Free Buds Manager.app"

# Signing. Ad-hoc by default. macOS ties permissions such as Accessibility to the signature: with an ad-hoc
# signature that is the build's own hash, so a permission is valid for the build it was given to, and the app
# offers to clear the old one after an update. A self-signed certificate does NOT help: macOS ignores it.
# A real certificate (Apple Development or Developer ID) keeps permissions across builds:
#   SIGN_IDENTITY="Developer ID Application: ..." [SIGN_KEYCHAIN=path] scripts/build-app.sh
IDENTITY="${SIGN_IDENTITY:--}"
BUNDLE_ID="io.github.edufigueiredos.FreeBudsManager"
KEYCHAIN_ARGS=()
REQUIREMENT_ARGS=()
# Ad-hoc, with the requirement spelled out as "this bundle id" instead of the default "this exact build".
# The permission macOS stores is that requirement, so it then survives rebuilds and updates.
[ "$IDENTITY" = "-" ] && REQUIREMENT_ARGS=(--requirements "=designated => identifier \"$BUNDLE_ID\"")
[ -n "${SIGN_KEYCHAIN:-}" ] && KEYCHAIN_ARGS=(--keychain "$SIGN_KEYCHAIN")

swift build -c release --product FreeBudsManager --arch arm64 --arch x86_64
BIN="$(swift build -c release --product FreeBudsManager --arch arm64 --arch x86_64 --show-bin-path)/FreeBudsManager"

# Guard: an empty main.swift builds fine and produces an app that quits at once.
SYMBOLS="$(nm "$BIN" 2>/dev/null || true)"   # not piped into `grep -q`: with pipefail it fails on SIGPIPE
case "$SYMBOLS" in *AppDelegate*) ;; *) echo "error: the app has no AppDelegate (is main.swift empty?)" >&2; exit 1;; esac

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FreeBudsManager"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/pt-BR.lproj "$APP/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --deep --options runtime \
    --entitlements Resources/FreeBudsManager.entitlements \
    ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} \
    ${REQUIREMENT_ARGS[@]+"${REQUIREMENT_ARGS[@]}"} \
    --sign "$IDENTITY" "$APP"

echo "Built $APP ($VERSION)"
