#!/bin/sh
# Builds build/BalanceKeeper.app from the Swift package.
set -e
cd "$(dirname "$0")/.."
APP=build/BalanceKeeper.app
swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/BalanceKeeper "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "OK: $APP"
