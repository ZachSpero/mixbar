#!/bin/bash
# Removes MixBar: quits the app (which restores your real output device),
# deletes the app and the audio driver, and restarts the audio system.
set -euo pipefail

echo "==> Quitting MixBar (restores your default output device)..."
osascript -e 'tell application "MixBar" to quit' >/dev/null 2>&1 || true
pkill -TERM -x MixBar >/dev/null 2>&1 || true
sleep 2

echo "==> Removing app and driver (sudo)..."
rm -rf /Applications/MixBar.app
sudo rm -rf "/Library/Audio/Plug-Ins/HAL/MixBar.driver"

echo "==> Restarting the audio system..."
sudo killall coreaudiod || true
sleep 2

echo "Done. If your sound output looks wrong, pick your speakers in"
echo "System Settings > Sound > Output."
