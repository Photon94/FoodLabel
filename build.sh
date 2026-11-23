#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
USB_PREFIX="${USB_PREFIX:-/opt/homebrew}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_OPTIONS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then SIGN_OPTIONS+=(--timestamp --options runtime); fi
APP_PATH="${APP_PATH:-${TMPDIR:-/tmp}/FoodLabel-build/FoodLabel.app}"
mkdir -p build/module-cache "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Frameworks" "$APP_PATH/Contents/Resources"
clang -target arm64-apple-macosx15.0 -Wall -Wextra -I"$USB_PREFIX/include/libusb-1.0" -c Sources/PrinterBridge.c -o build/PrinterBridge.o
swiftc -target arm64-apple-macosx15.0 -O -module-cache-path build/module-cache -import-objc-header Sources/PrinterBridge.h Sources/*.swift build/PrinterBridge.o -L"$USB_PREFIX/lib" -lusb-1.0 -o "$APP_PATH/Contents/MacOS/FoodLabel" -Xlinker -rpath -Xlinker @executable_path/../Frameworks
cp -f "$USB_PREFIX/lib/libusb-1.0.0.dylib" "$APP_PATH/Contents/Frameworks/"
USB_LINK=$(otool -L "$APP_PATH/Contents/MacOS/FoodLabel" | awk '/libusb-1.0.0.dylib/{print $1; exit}')
install_name_tool -change "$USB_LINK" '@rpath/libusb-1.0.0.dylib' "$APP_PATH/Contents/MacOS/FoodLabel"
install_name_tool -id '@rpath/libusb-1.0.0.dylib' "$APP_PATH/Contents/Frameworks/libusb-1.0.0.dylib"
cp Packaging/Info.plist "$APP_PATH/Contents/"
cp Packaging/THIRD-PARTY.txt Packaging/libusb-COPYING.txt "$APP_PATH/Contents/Resources/"
swiftc -module-cache-path build/module-cache Packaging/Icon.swift -o build/make-icon
build/make-icon
iconutil -c icns build/AppIcon.iconset -o "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign "${SIGN_OPTIONS[@]}" "$APP_PATH/Contents/Frameworks/libusb-1.0.0.dylib"
if xattr -p com.apple.FinderInfo "$APP_PATH" >/dev/null 2>&1; then
    xattr -d com.apple.FinderInfo "$APP_PATH"
fi
codesign "${SIGN_OPTIONS[@]}" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
printf 'Built %s\n' "$APP_PATH"
