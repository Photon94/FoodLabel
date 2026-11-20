#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
swiftc -module-cache-path build/module-cache Sources/Models.swift Sources/LabelRenderer.swift Sources/Database.swift Tests/CoreTests.swift -o build/core-tests
build/core-tests
swiftc -module-cache-path build/module-cache Sources/Models.swift Sources/LabelRenderer.swift Sources/Database.swift Tests/QRTests.swift -o build/qr-tests
build/qr-tests
clang -target arm64-apple-macosx15.0 -I/opt/homebrew/include/libusb-1.0 -c Sources/PrinterBridge.c -o build/PrinterBridge.o
swiftc -module-cache-path build/module-cache -import-objc-header Sources/PrinterBridge.h Sources/Models.swift Sources/LabelRenderer.swift Sources/Database.swift Sources/PrinterService.swift Sources/AppModel.swift Tests/ReviewTests.swift build/PrinterBridge.o -L/opt/homebrew/lib -lusb-1.0 -o build/review-tests
build/review-tests
