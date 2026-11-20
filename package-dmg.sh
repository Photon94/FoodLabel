#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DIST_DIR="${DIST_DIR:-$PWD/dist}"
mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/FoodLabel-$VERSION-arm64.dmg"
if [ -e "$DMG_PATH" ]; then
    printf 'Refusing to replace existing release: %s\n' "$DMG_PATH" >&2
    exit 1
fi
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/FoodLabel-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP_PATH="$STAGING/FoodLabel.app" SIGN_IDENTITY="$SIGN_IDENTITY" bash build.sh
mkdir -p "$STAGING/volume"
mv "$STAGING/FoodLabel.app" "$STAGING/volume/"
ln -s /Applications "$STAGING/volume/Applications"
cp Packaging/Install.txt "$STAGING/volume/Install.txt"
hdiutil create -volname FoodLabel -srcfolder "$STAGING/volume" -format UDZO "$DMG_PATH"
if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
    codesign --verify --strict "$DMG_PATH"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
    if [ "$SIGN_IDENTITY" = "-" ]; then
        printf 'Notarization requires SIGN_IDENTITY for a Developer ID certificate.\n' >&2
        exit 1
    fi
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 20m
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi
hdiutil verify "$DMG_PATH"
(cd "$DIST_DIR" && shasum -a 256 "FoodLabel-$VERSION-arm64.dmg" > SHA256SUMS.txt)
printf 'Release image: %s\n' "$DMG_PATH"
