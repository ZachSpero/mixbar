#!/bin/bash
# Builds MixBar.app from the SPM release build. No Xcode required.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP=build/MixBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/MixBar "$APP/Contents/MacOS/MixBar"
cp app/Info.plist "$APP/Contents/"
cp app/MixBar.icns "$APP/Contents/Resources/MixBar.icns"

codesign --force --sign - "$APP"

echo "Built $APP"
