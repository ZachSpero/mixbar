#!/bin/bash
# MixBar one-command build + install.
#
# Builds the audio driver and the app from source (Command Line Tools only,
# no Xcode needed), installs the driver into /Library/Audio/Plug-Ins/HAL
# (asks for your password), restarts the audio system, installs MixBar.app
# into /Applications, and launches it.
set -euo pipefail

cd "$(dirname "$0")"

HAL_DIR="/Library/Audio/Plug-Ins/HAL"
DRIVER="$HAL_DIR/MixBar.driver"

echo "==> Checking for Command Line Tools..."
if ! command -v clang++ >/dev/null || ! command -v swift >/dev/null; then
    echo "Command Line Tools not found. Run: xcode-select --install" >&2
    exit 1
fi

echo "==> Building driver..."
make -C driver

echo "==> Building app..."
./scripts/bundle-app.sh

NEED_DRIVER_INSTALL=1
if [ -d "$DRIVER" ]; then
    if diff -rq "$DRIVER/Contents/MacOS" build/MixBar.driver/Contents/MacOS >/dev/null 2>&1; then
        echo "==> Driver unchanged, skipping reinstall."
        NEED_DRIVER_INSTALL=0
    fi
fi

if [ "$NEED_DRIVER_INSTALL" = 1 ]; then
    echo "==> Installing driver (sudo)..."
    sudo rm -rf "$DRIVER"
    sudo cp -R build/MixBar.driver "$HAL_DIR/"

    echo "==> Restarting the audio system (audio will blip for a second)..."
    sudo killall coreaudiod
    sleep 3
fi

echo "==> Verifying the MixBar device exists..."
if ! system_profiler SPAudioDataType 2>/dev/null | grep -q "MixBar:"; then
    echo "MixBar device not found after install. Check Console.app for" >&2
    echo "coreaudiod errors mentioning MixBar.driver." >&2
    exit 1
fi

echo "==> Installing MixBar.app..."
osascript -e 'tell application "MixBar" to quit' >/dev/null 2>&1 || true
pkill -TERM -x MixBar >/dev/null 2>&1 || true
sleep 2
rm -rf /Applications/MixBar.app
cp -R build/MixBar.app /Applications/

echo "==> Launching MixBar..."
open /Applications/MixBar.app

echo
echo "Done. Look for the sliders icon in your menu bar."
echo "MixBar is now your output device; pick your real speakers inside MixBar."
